require "csv"
require "set"

class DatasetVersionImportService
  SUPPORTED_EXTENSIONS = %w[.csv .xls .xlsx .pdf].freeze
  MAX_FILE_SIZE = 20.megabytes
  MAX_RECORDS = 25_000

  def initialize(dataset:, user:, upload: nil, manual_records: nil, change_note: nil, source_kind: nil,
                 source_filename: nil, source_content_type: nil, source_content: nil, allow_empty: false,
                 append_records: false, display_name: nil, skip_boundary_link_state: false, skip_audit_log: false)
    @dataset = dataset
    @user = user
    @upload = upload
    @manual_records = manual_records
    @change_note = change_note
    @source_kind = source_kind || (upload.present? ? "file" : "manual")
    @source_filename = source_filename
    @source_content_type = source_content_type
    @source_content = source_content
    @allow_empty = allow_empty
    @append_records = append_records
    @display_name = display_name
    @skip_boundary_link_state = skip_boundary_link_state
    @skip_audit_log = skip_audit_log
  end

  def import!
    previous_current_version_id = @dataset.current_version_id
    previous_records_for_audit = current_records
    rows = @upload.present? ? rows_from_upload : rows_from_manual
    rows = current_records + rows if @append_records
    raise ArgumentError, "นำเข้าได้ไม่เกิน #{MAX_RECORDS.to_fs(:delimited)} รายการต่อ Version" if rows.size > MAX_RECORDS
    records, errors = normalize(rows)
    raise ArgumentError, errors.first(20).join(" · ") if errors.any?
    raise ArgumentError, "ไม่พบข้อมูลสำหรับนำเข้า" if records.empty? && !@allow_empty
    records = prepare_incident_records(records) if @dataset.data_type == "incidents"

    working_version = reusable_manual_version
    if working_version
      previous_version_state = manual_version_state(working_version)
      replace_record_documents(working_version, records)
      working_version.update!(
        user_id: @user.id,
        record_count: records.size,
        validation_summary: validation_summary(records),
        change_note: @change_note.presence || working_version.change_note,
        change_history: Array(working_version.change_history) + [change_history_entry(records)]
      )
      version = working_version
    else
      version = @dataset.versions.create!(
        user_id: @user.id,
        version_number: @dataset.versions.max(:version_number).to_i + 1,
        source_kind: @source_kind,
        source_filename: @source_filename || @upload&.original_filename,
        source_content_type: @source_content_type || @upload&.content_type,
        display_name: new_version_display_name,
        record_count: records.size,
        validation_summary: validation_summary(records),
        change_note: @change_note.presence,
        change_history: @source_kind == "manual" ? [change_history_entry(records)] : []
      )
      replace_record_documents(version, records)
      content = @source_content || begin @upload&.rewind; @upload&.read end
      version.update!(source_file_id: DatasetGridFileStore.upload(version.source_filename, content,
        content_type: version.source_content_type)) if content.present?
    end
    @dataset.update!(current_version_id: version.id)
    ImportedIncidentSyncService.new(dataset: @dataset, user: @user, records: records).sync! if @dataset.data_type == "incidents"
    record_audit_logs!(previous_records_for_audit, records, version) unless @skip_audit_log
    update_boundary_link_state!(previous_records_for_audit, records)
    version
  rescue StandardError
    if working_version && previous_version_state
      restore_manual_version(working_version, previous_version_state)
    elsif version
      @dataset.set(current_version_id: previous_current_version_id) if @dataset.persisted?
      version.destroy
    end
    raise
  end

  def validate_records(rows)
    normalize(rows)
  end

  private

  def reusable_manual_version
    return unless @source_kind == "manual"

    current = @dataset.current_version
    current if current&.source_kind == "manual"
  end

  def default_display_name
    "#{base_display_name} #{Time.zone.today.strftime('%d-%m-%Y')}"
  end

  def base_display_name
    if @dataset.data_type == "custom"
      @dataset.name
    else
      ImportedDataset::TYPE_LABELS.fetch(@dataset.data_type, @dataset.name)
    end
  end

  def new_version_display_name
    requested_name = @display_name.to_s.strip.presence
    return requested_name if requested_name

    if @source_kind == "manual"
      current_version = @dataset.current_version
      previous_name = current_version&.display_name.to_s.strip.presence || @dataset.name.to_s.strip.presence if current_version
      return manual_display_name(previous_name) if previous_name
    end

    @source_kind == "file" ? default_display_name : base_display_name
  end

  def manual_display_name(previous_name)
    current_date = Time.zone.today.strftime("%d-%m-%Y")
    previous_name.sub(/\d{2}-\d{2}-\d{4}\z/, current_date)
  end

  def validation_summary(records)
    { "total" => records.size, "valid" => records.size, "invalid" => 0 }
  end

  def change_history_entry(records)
    {
      "user_id" => @user.id,
      "username" => @user.username,
      "note" => @change_note.presence || "ปรับปรุงข้อมูลด้วยตนเอง",
      "record_count" => records.size,
      "changed_at" => Time.current.utc.iso8601
    }
  end

  def manual_version_state(version)
    {
      records: version.records.map(&:deep_dup),
      user_id: version.user_id,
      record_count: version.record_count,
      validation_summary: version.validation_summary.deep_dup,
      change_note: version.change_note,
      change_history: Array(version.change_history).map(&:deep_dup)
    }
  end

  def restore_manual_version(version, state)
    replace_record_documents(version, state[:records])
    version.set(state.except(:records))
  rescue StandardError => error
    Rails.logger.error("Unable to restore manual dataset version #{version.id}: #{error.class}: #{error.message}")
  end

  def replace_record_documents(version, records)
    version.record_documents.delete_all
    documents = records.each_with_index.map do |record, index|
      { imported_dataset_version_id: version.id, position: index, payload: record,
        location: record_location(record), created_at: Time.current }
    end
    ImportedDatasetRecord.collection.insert_many(documents) if documents.any?
  end

  def rows_from_upload
    DatasetFilePreviewService.new(@upload).parse![:rows]
  end

  def rows_from_manual
    value = @manual_records.is_a?(String) ? JSON.parse(@manual_records) : @manual_records
    rows = Array(value)
    rows
  rescue JSON::ParserError
    raise ArgumentError, "ข้อมูลที่กรอกไม่อยู่ในรูปแบบที่ถูกต้อง"
  end

  def current_records
    Array(@dataset.current_version&.records).map(&:deep_dup)
  end

  def normalize(rows)
    errors = []
    used_sensor_ids = Set.new
    records = rows.each_with_index.filter_map do |raw, index|
      raw = raw.to_h.stringify_keys
      normalized = {}
      @dataset.effective_schema_definition.each do |field|
        next if field["generated"] || (@dataset.data_type == "incidents" && %w[reference_code status].include?(field["key"]))

        source_value = raw[field["key"]]
        source_value = raw[field["label"]] if source_value.blank?
        if field["required"] && source_value.blank?
          errors << "แถว #{index + 2}: #{field['label']} จำเป็นต้องกรอก"
        end
        normalized[field["key"]] = cast(source_value, field["type"])
      rescue ArgumentError
        errors << "แถว #{index + 2}: #{field['label']} มีชนิดข้อมูลไม่ถูกต้อง"
      end
      normalized["reference_code"] = raw["reference_code"] if @dataset.data_type == "incidents" && raw["reference_code"].present?
      if @dataset.data_type == "population"
        %w[boundary_status boundary_dataset_id boundary_record_id boundary_record_position].each do |key|
          normalized[key] = raw[key] if raw[key].present?
        end
        normalized["boundary_status"] ||= "ยังไม่เชื่อมขอบเขต"
      end
      if @dataset.data_type == "village_boundaries"
        normalized["boundary_source"] = raw["boundary_source"].presence || (@source_kind == "file" ? "อัปโหลดไฟล์" : "วาดขอบเขตเอง")
      end
      assign_registry_code(normalized, raw)
      normalized["record_id"] = raw["record_id"].presence || existing_record_id(normalized, raw) || SecureRandom.uuid
      if device_dataset?
        sensor_id = normalized["sensor_id"].to_s.strip.downcase
        errors << "แถว #{index + 2}: Sensor ID ซ้ำในชุดข้อมูล" if sensor_id.present? && used_sensor_ids.include?(sensor_id)
        used_sensor_ids << sensor_id if sensor_id.present?
      end
      if @dataset.data_type == "consumables"
        errors << "แถว #{index + 2}: จำนวนคงเหลือต้องไม่น้อยกว่า 0" if normalized["current_quantity"].to_f.negative?
        errors << "แถว #{index + 2}: จุดแจ้งเตือนขั้นต่ำต้องไม่น้อยกว่า 0" if normalized["minimum_quantity"].to_f.negative?
      end
      validate_boundary_geometry(normalized, index, errors) if @dataset.data_type == "village_boundaries"
      validate_location(normalized, index, errors)
      normalized unless normalized.values.all?(&:blank?)
    end
    [records, errors]
  end

  def prepare_incident_records(records)
    used_codes = []
    records.map do |source_record|
      record = source_record.deep_dup
      code = record["reference_code"].presence || next_incident_reference_code(used_codes)
      existing = Incident.where(reference_code: code).first
      if existing && existing.imported_dataset_id != @dataset.id.to_s
        raise ArgumentError, "รหัสเหตุการณ์ #{code} ถูกใช้งานแล้ว"
      end
      raise ArgumentError, "รหัสเหตุการณ์ #{code} ซ้ำกันในไฟล์" if used_codes.include?(code)

      ImportedIncidentSyncService.parse_occurred_at(record["occurred_at"])
      ImportedIncidentSyncService.normalize_severity(record["severity"])
      record["status"] = existing&.status.presence || "pending"
      ImportedIncidentSyncService.normalize_status(record["status"])
      record["reference_code"] = code
      used_codes << code
      record
    end
  end

  def assign_registry_code(record, raw)
    if device_dataset?
      record["token"] = raw["token"].presence || SecureRandom.urlsafe_base64(32)
      return
    end

    key, prefix = case @dataset.data_type
                  when "agencies" then ["agency_code", "AG"]
                  when "teams" then ["team_code", "TEAM"]
                  when "workforce" then ["personnel_code", "PER"]
                  when "resources" then ["code", "RES"]
                  when "consumables" then ["consumable_code", "MAT"]
                  end
    return unless key

    record[key] = raw[key].presence || "#{prefix}-#{SecureRandom.hex(3).upcase}"
  end

  def device_dataset?
    %w[cctv_devices water_level_sensors pm25_sensors].include?(@dataset.data_type)
  end

  def next_incident_reference_code(used_codes)
    loop do
      code = "INC-#{Time.current.year + 543}-#{SecureRandom.hex(3).upcase}"
      return code unless used_codes.include?(code) || Incident.where(reference_code: code).exists?
    end
  end

  def cast(value, type)
    return nil if value.blank?
    case type
    when "number" then Float(normalized_numeric_value(value))
    when "integer"
      number = Float(normalized_numeric_value(value))
      raise ArgumentError unless number.finite? && number == number.to_i
      number.to_i
    when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
    when "date" then Date.parse(value.to_s).iso8601
    else value.to_s.strip
    end
  end

  def normalized_numeric_value(value)
    return value unless value.is_a?(String)

    value.strip.delete(",")
  end

  def validate_location(record, index, errors)
    return unless @dataset.geometry_type == "point"
    lat, lon = record["latitude"], record["longitude"]
    if lat.blank? || lon.blank? || !lat.to_f.between?(-90, 90) || !lon.to_f.between?(-180, 180)
      errors << "แถว #{index + 2}: พิกัดไม่ถูกต้อง"
      return
    end
    return if @user.system_admin? || point_inside_access_boundary?(lon, lat)
    errors << "แถว #{index + 2}: พิกัดอยู่นอกพื้นที่รับผิดชอบ"
  end

  def validate_boundary_geometry(record, index, errors)
    geometry = JSON.parse(record["geometry"].to_s)
    type = geometry["type"]
    unless %w[Polygon MultiPolygon].include?(type)
      errors << "แถว #{index + 2}: ขอบเขตต้องเป็น Polygon หรือ MultiPolygon"
      return
    end
    if geometry["coordinates"].blank?
      errors << "แถว #{index + 2}: ขอบเขตไม่มีพิกัด"
      return
    end
    return if @user.system_admin?

    boundary = @user.access_boundary
    if boundary.blank?
      errors << "แถว #{index + 2}: บัญชีนี้ยังไม่มีขอบเขตพื้นที่ดูแล"
      return
    end
    query = <<~SQL.squish
      WITH village_geometry AS (
        SELECT ST_SetSRID(ST_GeomFromGeoJSON(?), 4326) AS geometry
      )
      SELECT ST_IsValid(geometry) AND ST_Covers(?::geometry, geometry)
      FROM village_geometry
    SQL
    sql = ActiveRecord::Base.sanitize_sql_array([query, geometry.to_json, boundary])
    errors << "แถว #{index + 2}: ขอบเขตหมู่บ้านต้องอยู่ภายในพื้นที่ดูแล" unless ActiveRecord::Base.connection.select_value(sql)
  rescue JSON::ParserError
    errors << "แถว #{index + 2}: ขอบเขต GeoJSON ไม่ถูกต้อง"
  rescue ActiveRecord::StatementInvalid
    errors << "แถว #{index + 2}: ไม่สามารถตรวจสอบขอบเขต GeoJSON ได้"
  end

  def point_inside_access_boundary?(lon, lat)
    boundary = @user.access_boundary
    return false unless boundary
    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT ST_Covers(?::geography, ST_SetSRID(ST_Point(?, ?), 4326)::geography)", boundary, lon, lat
    ])
    ActiveRecord::Base.connection.select_value(sql)
  end

  def record_location(record)
    return unless @dataset.geometry_type == "point"
    [record["longitude"].to_f, record["latitude"].to_f]
  end

  def record_audit_logs!(before_records, after_records, version)
    if %w[file restored checkpoint].include?(@source_kind)
      action = { "file" => "import", "restored" => "restore", "checkpoint" => "checkpoint" }.fetch(@source_kind)
      DatasetChangeLog.create!(imported_dataset_id: @dataset.id, imported_dataset_version_id: version.id,
        user_id: @user.id, action: action, source_kind: @source_kind, note: @change_note,
        before_data: { "record_count" => before_records.size }, after_data: { "record_count" => after_records.size })
      return
    end

    before_by_id = before_records.index_by { |record| record["record_id"] }
    after_by_id = after_records.index_by { |record| record["record_id"] }
    entries = []
    (before_by_id.keys | after_by_id.keys).each do |record_id|
      before_record = before_by_id[record_id]
      after_record = after_by_id[record_id]
      action = before_record.nil? ? "add" : after_record.nil? ? "delete" : "update"
      changed_fields = changed_record_fields(before_record, after_record)
      next if action == "update" && changed_fields.empty?

      record = after_record || before_record
      entries << { imported_dataset_id: @dataset.id, imported_dataset_version_id: version.id,
        user_id: @user.id, action: action, source_kind: @source_kind, record_id: record_id,
        record_label: audit_record_label(record), before_data: before_record || {}, after_data: after_record || {},
        changed_fields: changed_fields, note: @change_note, created_at: Time.current }
    end
    DatasetChangeLog.collection.insert_many(entries) if entries.any?
  end

  def changed_record_fields(before_record, after_record)
    generated_fields = @dataset.effective_schema_definition.filter_map { |field| field["key"] if field["generated"] }
    internal_fields = (%w[record_id boundary_dataset_id boundary_record_id boundary_record_position] + generated_fields).uniq
    return Array(after_record&.keys).reject { |key| internal_fields.include?(key) } if before_record.nil?
    return Array(before_record&.keys).reject { |key| internal_fields.include?(key) } if after_record.nil?

    (before_record.keys | after_record.keys).reject { |key| internal_fields.include?(key) || before_record[key] == after_record[key] }
  end

  def audit_record_label(record)
    @dataset.record_display_label(record)
  end

  def existing_record_id(normalized, raw)
    key = record_identity_key(normalized.merge(raw.slice("record_id", "reference_code")))
    return if key.blank?

    @existing_record_ids ||= current_records.filter_map do |record|
      identity = record_identity_key(record)
      [identity, record["record_id"]] if identity.present? && record["record_id"].present?
    end.to_h
    @existing_record_ids[key]
  end

  def record_identity_key(record)
    values = case @dataset.data_type
             when "population", "village_boundaries"
               [record["village_code"].presence || record["subdistrict_code"].presence || record["subdistrict"], record["village_number"].presence || record["village_name"]]
             when "cctv_devices", "water_level_sensors", "pm25_sensors" then [record["sensor_id"]]
             when "agencies" then [record["agency_code"].presence || record["agency_name"]]
             when "teams" then [record["team_code"].presence || record["team_name"]]
             when "workforce" then [record["personnel_code"].presence || record["full_name"], record["agency_code"]]
             when "resources" then [record["code"].presence || record["name"], record["agency_code"]]
             when "consumables" then [record["consumable_code"].presence || record["name"], record["agency_code"]]
             when "incidents" then [record["reference_code"]]
             else []
             end
    normalized = values.map { |value| value.to_s.strip.downcase }.reject(&:blank?)
    normalized.join("|").presence
  end

  def update_boundary_link_state!(before_records, after_records)
    return if @skip_boundary_link_state || !%w[population village_boundaries].include?(@dataset.data_type)
    return unless boundary_matching_inputs(before_records) != boundary_matching_inputs(after_records)

    if @dataset.data_type == "population"
      @dataset.set(boundary_link_status: "needs_matching", boundary_linked_at: nil,
        linked_boundary_dataset_id: nil, linked_population_version_id: nil, linked_boundary_version_id: nil)
    else
      scope = ImportedDataset.where(data_type: "population", subdistrict_id: @dataset.subdistrict_id)
      scope.update_all(boundary_link_status: "needs_matching", boundary_linked_at: nil,
        linked_boundary_dataset_id: nil, linked_population_version_id: nil, linked_boundary_version_id: nil)
    end
  end

  def boundary_matching_inputs(records)
    Array(records).map do |record|
      [record["record_id"], record["village_code"], record["subdistrict_code"], record["subdistrict"],
       record["village_number"], record["village_name"]].map(&:to_s)
    end.sort
  end
end

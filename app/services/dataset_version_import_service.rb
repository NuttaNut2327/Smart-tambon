require "csv"

class DatasetVersionImportService
  SUPPORTED_EXTENSIONS = %w[.csv .xls .xlsx .pdf].freeze
  MAX_FILE_SIZE = 20.megabytes
  MAX_RECORDS = 25_000

  def initialize(dataset:, user:, upload: nil, manual_records: nil, change_note: nil, source_kind: nil,
                 source_filename: nil, source_content_type: nil, source_content: nil, allow_empty: false,
                 append_records: false)
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
  end

  def import!
    previous_current_version_id = @dataset.current_version_id
    rows = @upload.present? ? rows_from_upload : rows_from_manual
    rows = current_records + rows if @append_records
    raise ArgumentError, "นำเข้าได้ไม่เกิน #{MAX_RECORDS.to_fs(:delimited)} รายการต่อ Version" if rows.size > MAX_RECORDS
    records, errors = normalize(rows)
    raise ArgumentError, errors.first(20).join(" · ") if errors.any?
    raise ArgumentError, "ไม่พบข้อมูลสำหรับนำเข้า" if records.empty? && !@allow_empty
    records = prepare_incident_records(records) if @dataset.data_type == "incidents"

    version = @dataset.versions.create!(
        user_id: @user.id,
        version_number: @dataset.versions.max(:version_number).to_i + 1,
        source_kind: @source_kind,
        source_filename: @source_filename || @upload&.original_filename,
        source_content_type: @source_content_type || @upload&.content_type,
        record_count: records.size,
        validation_summary: { "total" => records.size, "valid" => records.size, "invalid" => 0 },
        change_note: @change_note.presence
      )
    documents = records.each_with_index.map do |record, index|
      { imported_dataset_version_id: version.id, position: index, payload: record,
        location: record_location(record), created_at: Time.current }
    end
    ImportedDatasetRecord.collection.insert_many(documents) if documents.any?
    content = @source_content || begin @upload&.rewind; @upload&.read end
    version.update!(source_file_id: DatasetGridFileStore.upload(version.source_filename, content,
      content_type: version.source_content_type)) if content.present?
    @dataset.update!(current_version_id: version.id)
    ImportedIncidentSyncService.new(dataset: @dataset, user: @user, records: records).sync! if @dataset.data_type == "incidents"
    version
  rescue StandardError
    @dataset.set(current_version_id: previous_current_version_id) if version && @dataset.persisted?
    version&.destroy
    raise
  end

  def validate_records(rows)
    normalize(rows)
  end

  private

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
        %w[boundary_status boundary_dataset_id boundary_record_position].each do |key|
          normalized[key] = raw[key] if raw[key].present?
        end
        normalized["boundary_status"] ||= "ยังไม่เชื่อมขอบเขต"
      end
      if @dataset.data_type == "village_boundaries"
        normalized["boundary_source"] = raw["boundary_source"].presence || (@source_kind == "file" ? "อัปโหลดไฟล์" : "วาดขอบเขตเอง")
      end
      assign_registry_code(normalized, raw)
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

  def next_incident_reference_code(used_codes)
    loop do
      code = "INC-#{Time.current.year + 543}-#{SecureRandom.hex(3).upcase}"
      return code unless used_codes.include?(code) || Incident.where(reference_code: code).exists?
    end
  end

  def cast(value, type)
    return nil if value.blank?
    case type
    when "number" then Float(value)
    when "integer"
      number = Float(value)
      raise ArgumentError unless number.finite? && number == number.to_i
      number.to_i
    when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
    when "date" then Date.parse(value.to_s).iso8601
    else value.to_s.strip
    end
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
end

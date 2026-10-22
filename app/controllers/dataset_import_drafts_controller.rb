class DatasetImportDraftsController < ApplicationController
  FILE_RELATION_FIELDS = {
    "teams" => %w[agency_code agency_name],
    "workforce" => %w[agency_code agency_name team_code team_name],
    "resources" => %w[agency_code responsible_person],
    "consumables" => %w[agency_code agency_name]
  }.freeze
  before_action :require_importer!
  before_action :set_draft, only: %i[validate preview finalize destroy]

  def manual
    data_type = normalized_type
    record = params.require(:record).to_unsafe_h
    if data_type == "village_boundaries" && record["geometry"].blank?
      raise ArgumentError, "กรุณาวาดขอบเขตหรืออัปโหลดไฟล์ GeoJSON ก่อนบันทึก"
    end
    map_enabled = ActiveModel::Type::Boolean.new.cast(params[:map_enabled]) || false
    target = destination_dataset(data_type, map_enabled)
    records = Array(target.current_version&.records) + [record]
    version = DatasetVersionImportService.new(dataset: target, user: current_user, manual_records: records,
      source_kind: "manual", change_note: params[:change_note].presence || "เพิ่มข้อมูลด้วยตนเอง").import!
    render json: { dataset_id: target.id.to_s, version: version.version_number, records: version.record_count,
                   redirect_url: data_layers_path(data_type: data_type) }
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound, Mongoid::Errors::DocumentNotFound, Mongoid::Errors::Validations, ArgumentError => error
    target&.destroy if @destination_dataset_created && target&.persisted? && target.current_version_id.blank?
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    data_type, schema, target_dataset_id = draft_context
    import_context = resolved_import_context(data_type)
    upload = params.require(:file)
    parsed = DatasetFilePreviewService.new(upload).parse!
    mapping = suggested_mapping(parsed[:headers], schema)
    upload.rewind
    file_id = DatasetGridFileStore.upload(upload.original_filename, upload.read, content_type: upload.content_type)
    draft = DatasetImportDraft.create!(user_id: current_user.id, data_type: data_type,
      target_dataset_id: target_dataset_id, schema_definition: schema,
      import_context: import_context,
      source_filename: upload.original_filename, source_content_type: upload.content_type,
      source_file_id: file_id, source_headers: parsed[:headers], column_mapping: mapping, expires_at: 2.hours.from_now)
    documents = parsed[:rows].each_with_index.map do |row, index|
      { dataset_import_draft_id: draft.id, position: index, raw_payload: row, ready_for_import: false }
    end
    DatasetImportDraftRow.collection.insert_many(documents)
    render json: draft_payload(draft)
  rescue ActionController::ParameterMissing, Mongoid::Errors::Validations, ArgumentError => error
    draft&.destroy
    DatasetGridFileStore.delete(file_id) if defined?(file_id) && file_id
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def validate
    mapping = params.fetch(:mapping, {}).to_unsafe_h.stringify_keys
    mapped_entries = @draft.rows.asc(:position).filter_map do |draft_row|
      mapped = mapping.each_with_object({}) do |(target, source), result|
        result[target] = draft_row.raw_payload[source] if source.present?
      end
      mapped.merge!(@draft.import_context)
      { draft_row: draft_row, mapped: mapped } unless mapped.values.all?(&:blank?)
    end
    mapped_rows = mapped_entries.map { |entry| entry[:mapped] }
    target_geometry = if @draft.data_type == "custom"
                        custom_target_dataset.geometry_type
                      elsif @draft.data_type == "village_boundaries"
                        "polygon"
                      else
                        "none"
                      end
    preview_dataset = ImportedDataset.new(user: current_user, name: "preview", data_type: @draft.data_type,
      geometry_type: target_geometry, schema_definition: @draft.schema, map_enabled: target_geometry != "none")
    registry_records = @draft.data_type == "agencies" ? current_agency_records : nil
    records, errors = DatasetVersionImportService.new(dataset: preview_dataset, user: current_user,
      registry_records: registry_records).validate_records(mapped_rows)
    missing = @draft.schema.select { |field| field["required"] && mapping[field["key"]].blank? }
    errors.unshift(*missing.map { |field| "ยังไม่ได้จับคู่คอลัมน์ #{field['label']}" })
    summary = { "total" => mapped_rows.size, "valid" => errors.empty? ? records.size : 0,
                "invalid" => errors.size, "errors" => errors.first(30) }
    summary["agency_impact"] = agency_import_impact(registry_records, records) if @draft.data_type == "agencies" && errors.empty?
    @draft.rows.update_all(ready_for_import: false, validated_payload: {})
    if errors.empty?
      mapped_entries.each_with_index do |entry, index|
        entry[:draft_row].set(ready_for_import: true, validated_payload: records[index])
      end
    end
    @draft.update!(column_mapping: mapping, validation_summary: summary)
    render json: draft_payload(@draft)
  end

  def preview = render json: draft_payload(@draft)

  def finalize
    records = @draft.validated_records
    raise ArgumentError, "กรุณาตรวจสอบข้อมูลให้ผ่านก่อนนำเข้า" if records.empty?
    records.each { |record| record["boundary_source"] = "อัปโหลดไฟล์" } if @draft.data_type == "village_boundaries"
    map_enabled = ActiveModel::Type::Boolean.new.cast(params[:map_enabled]) || false
    target = @draft.data_type == "custom" ? custom_target_dataset : destination_dataset(@draft.data_type, map_enabled)
    source_content = DatasetGridFileStore.download(@draft.source_file_id)
    import_mode = params[:import_mode].to_s.presence_in(%w[insert upsert replace]) || "insert"
    version = DatasetVersionImportService.new(dataset: target, user: current_user, manual_records: records,
      source_kind: "file", source_filename: @draft.source_filename, source_content_type: @draft.source_content_type,
      source_content: source_content, change_note: params[:change_note].presence || "นำเข้าจาก #{@draft.source_filename}",
      import_mode: import_mode, display_name: params[:version_name]).import!
    next_url = data_layers_path(data_type: @draft.data_type)
    @draft.destroy
    render json: { dataset_id: target.id.to_s, version: version.version_number, records: version.record_count,
                   redirect_url: next_url }
  rescue ActiveRecord::RecordNotFound, Mongoid::Errors::DocumentNotFound
    render json: { error: "ไม่พบชุดข้อมูลที่เลือก" }, status: :not_found
  rescue Mongoid::Errors::Validations, ArgumentError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def destroy
    @draft.destroy
    head :no_content
  end

  private

  def set_draft
    @draft = DatasetImportDraft.active.where(user_id: current_user.id).find(params[:id])
  end

  def normalized_type
    type = params[:data_type].to_s
    raise ArgumentError, "ประเภทชุดข้อมูลไม่ถูกต้อง" unless ImportedDataset::STANDARD_SCHEMAS.key?(type)
    type
  end

  def draft_context
    if params[:target_dataset_id].blank?
      type = normalized_type
      excluded = FILE_RELATION_FIELDS.fetch(type, [])
      schema = ImportedDataset.schema_for(type).reject { |field| field["generated"] || excluded.include?(field["key"]) }
      return [type, schema, nil]
    end

    dataset = editable_dataset_scope.find(params[:target_dataset_id])
    raise ArgumentError, "รองรับ Mapping แบบกำหนดเองเฉพาะชุดข้อมูลที่ผู้ใช้แก้ไขได้" unless dataset.data_type == "custom"
    [dataset.data_type, dataset.effective_schema_definition, dataset.id]
  end

  def resolved_import_context(data_type)
    return {} unless FILE_RELATION_FIELDS.key?(data_type)

    agency_code = params[:agency_code].to_s.strip
    agency = current_agency_records.find { |record| record["agency_code"].to_s == agency_code }
    raise ArgumentError, "กรุณาเลือกหน่วยงานก่อนอัปโหลดไฟล์" unless agency

    context = { "agency_code" => agency["agency_code"], "agency_name" => agency["agency_name"] }
    context["responsible_person"] = agency["agency_name"] if data_type == "resources"
    return context unless data_type == "workforce"

    team_code = params[:team_code].to_s.strip
    team = current_team_records.find do |record|
      record["team_code"].to_s == team_code && record["agency_code"].to_s == agency_code
    end
    raise ArgumentError, "กรุณาเลือกทีมปฏิบัติงานของหน่วยงานที่เลือกก่อนอัปโหลดไฟล์" unless team

    context.merge("team_code" => team["team_code"], "team_name" => team["team_name"])
  end

  def custom_target_dataset
    raise ArgumentError, "ไม่พบชุดข้อมูลปลายทาง" if @draft.target_dataset_id.blank?
    editable_dataset_scope.find(@draft.target_dataset_id)
  end

  def editable_dataset_scope
    current_user.system_admin? ? ImportedDataset.all : ImportedDataset.where(:user_id.in => current_user.organization_user_ids)
  end

  def destination_dataset(data_type, map_enabled)
    device_dataset = %w[cctv_devices water_level_sensors pm25_sensors].include?(data_type)
    if data_type == "village_boundaries"
      map_enabled = true
      geometry_type = "polygon"
    elsif device_dataset
      geometry_type = "point"
    else
      geometry_type = map_enabled ? "point" : "none"
    end
    subdistrict = params[:subdistrict_id].present? ? Subdistrict.find(params[:subdistrict_id]) : current_user.subdistrict
    authorize_subdistrict!(subdistrict)

    candidates = if subdistrict
                   ImportedDataset.where(data_type: data_type, subdistrict_id: subdistrict.id).to_a
                 else
                   ImportedDataset.where(data_type: data_type, :user_id.in => current_user.organization_user_ids, subdistrict_id: nil).to_a
                 end
    if candidates.empty? && subdistrict
      # รองรับชุดข้อมูลเดิมที่สร้างก่อนระบบผูกชุดข้อมูลกับพื้นที่
      owner_scope = current_user.system_admin? ? ImportedDataset.all : ImportedDataset.where(:user_id.in => current_user.organization_user_ids)
      candidates = owner_scope.where(data_type: data_type, subdistrict_id: nil).to_a
    end
    dataset = candidates.max_by do |candidate|
      [candidate.current_version&.record_count.to_i, candidate.updated_at || Time.at(0)]
    end

    if dataset
      dataset.update!(name: ImportedDataset::TYPE_LABELS.fetch(data_type), subdistrict: subdistrict,
        map_enabled: map_enabled, geometry_type: geometry_type)
      return dataset
    end

    @destination_dataset_created = true
    ImportedDataset.create!(user: current_user, subdistrict: subdistrict,
      name: ImportedDataset::TYPE_LABELS.fetch(data_type), data_type: data_type,
      geometry_type: geometry_type, schema_definition: ImportedDataset.schema_for(data_type),
      map_enabled: map_enabled, shared_with_all: true)
  end

  def suggested_mapping(headers, schema)
    schema.reject { |field| field["generated"] }.to_h do |field|
      match = headers.find { |header| header.to_s.casecmp?(field["key"]) || header.to_s.casecmp?(field["label"]) }
      [field["key"], match]
    end
  end

  def current_agency_records
    scope = ImportedDataset.where(data_type: "agencies")
    scope = scope.where(:user_id.in => current_user.organization_user_ids) unless current_user.system_admin?
    datasets = scope.to_a
    if current_user.subdistrict_id.present?
      area_datasets = datasets.select { |dataset| dataset.subdistrict_id == current_user.subdistrict_id }
      datasets = area_datasets if area_datasets.any?
    end
    dataset = datasets.max_by { |candidate| [candidate.current_version&.record_count.to_i, candidate.updated_at || Time.at(0)] }
    Array(dataset&.current_version&.records).map(&:deep_dup)
  end

  def current_team_records
    scope = ImportedDataset.visible_to(current_user).where(data_type: "teams")
    scope.flat_map { |dataset| Array(dataset.current_version&.records).map(&:deep_dup) }
  end

  def agency_import_impact(previous_records, incoming_records)
    previous_by_code = Array(previous_records).index_by { |record| record["agency_code"].to_s.downcase }
    incoming_codes = Array(incoming_records).filter_map { |record| record["agency_code"].to_s.downcase.presence }.to_set
    retained_codes = previous_by_code.keys & incoming_codes.to_a
    removed_codes = previous_by_code.keys - incoming_codes.to_a
    new_codes = incoming_codes.to_a - previous_by_code.keys
    removed_original_codes = removed_codes.filter_map { |code| previous_by_code[code]["agency_code"].presence }
    referenced = agency_reference_counts(removed_original_codes)
    {
      "retained" => retained_codes.size,
      "new" => new_codes.size,
      "removed" => removed_codes.size,
      "removed_references" => referenced.values.sum,
      "references_by_type" => referenced,
      "removed_agencies" => removed_codes.first(20).map do |code|
        { "agency_code" => previous_by_code[code]["agency_code"], "agency_name" => previous_by_code[code]["agency_name"] }
      end
    }
  end

  def agency_reference_counts(codes)
    return {} if codes.empty?

    %w[teams workforce resources consumables].to_h do |type|
      datasets = ImportedDataset.visible_to(current_user).where(data_type: type).to_a
      version_ids = datasets.filter_map(&:current_version_id)
      count = if version_ids.empty?
                0
              else
                ImportedDatasetRecord.where(:imported_dataset_version_id.in => version_ids,
                  :"payload.agency_code".in => codes).count
              end
      [type, count]
    end
  end

  def draft_payload(draft)
    { id: draft.id.to_s, data_type: draft.data_type, filename: draft.source_filename,
      headers: draft.source_headers, schema: draft.schema, mapping: draft.column_mapping,
      sample: draft.source_rows.first(5), records: draft.validated_records.first(10), validation: draft.validation_summary,
      import_context: draft.import_context }
  end

  def require_importer!
    return if current_user.system_admin? || current_user.subdistrict_admin?
    render json: { error: "บัญชีนี้ไม่มีสิทธิ์นำเข้าข้อมูล" }, status: :forbidden
  end

  def authorize_subdistrict!(subdistrict)
    return if current_user.system_admin?
    raise ArgumentError, "กรุณาเลือกพื้นที่ที่รับผิดชอบ" unless subdistrict
    raise ArgumentError, "เลือกได้เฉพาะพื้นที่ที่รับผิดชอบ" unless current_user.accessible_subdistrict_ids.include?(subdistrict.id)
  end
end

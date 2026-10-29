# AI-assisted import: upload a spreadsheet, PDF or photo of a table → the AI reads it into columns, coordinates
# are parsed or geocoded inside the chosen subdistrict → the user corrects the table → it becomes a custom dataset.
class SmartImportsController < ApplicationController
  VISION_MODEL = /claude|gpt|vl|gemini|omni|vision|llava|pixtral/i

  before_action :require_importer!
  before_action :set_smart_import, only: %i[show update geocode finalize]

  def new
    @subdistricts = accessible_subdistricts
    @providers = AiProvider.enabled.ordered.to_a
    @recent = SmartImport.where(user_id: current_user.id).order_by(created_at: :desc).limit(5).to_a
  end

  def create
    upload = params.require(:file)
    subdistrict = Subdistrict.find_by(id: params[:subdistrict_id]) || current_user.subdistrict
    authorize_subdistrict!(subdistrict)
    llm, model = llm_for(params[:ai_provider_id], params[:model])

    table = SmartImports::Extractor.new(upload:, llm:, page_images: page_images).call
    columns = table[:columns].each_with_index.map { |column, index| column.transform_keys(&:to_s).merge("key" => "c#{index + 1}") }
    rows = table[:rows].first(SmartImport::MAX_ROWS).map { |row| columns.each_with_index.to_h { |column, index| [column["key"], row[index].to_s] } }
    SmartImports::GeoResolver.new(subdistrict).resolve(rows, columns)

    upload.rewind
    content = upload.read
    smart_import = SmartImport.create!(
      user_id: current_user.id, subdistrict_id: subdistrict&.id, ai_model: model, source_kind: table[:kind],
      name: params[:name].presence || table[:title].presence || File.basename(upload.original_filename.to_s, ".*"),
      source_filename: upload.original_filename, source_content_type: upload.content_type, columns:, rows:,
      source_file_id: DatasetGridFileStore.upload(upload.original_filename, content, content_type: upload.content_type),
      notes: table[:rows].size > SmartImport::MAX_ROWS ? ["นำเข้าได้สูงสุด #{SmartImport::MAX_ROWS.to_fs(:delimited)} แถว ส่วนที่เกินถูกตัดออก"] : []
    )
    render json: { url: smart_import_path(smart_import) }
  rescue SmartImports::Extractor::Error, ArgumentError, ActionController::ParameterMissing => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    @subdistrict = @smart_import.subdistrict
  end

  def update
    @smart_import.update!(editor_params)
    render json: { ok: true }
  end

  # Re-reads coordinates or re-geocodes the given rows (all rows when none are given) after the user edits them.
  def geocode
    @smart_import.assign_attributes(editor_params)
    resolver = SmartImports::GeoResolver.new(@smart_import.subdistrict)
    indices = Array(params[:indices]).map(&:to_i).presence || @smart_import.rows.each_index.to_a
    rows = @smart_import.rows.map(&:dup)
    indices.each do |index|
      next unless rows[index]

      params[:manual] ? resolver.check_manual(rows[index]) : resolver.resolve_row(rows[index], @smart_import.columns)
    end
    @smart_import.update!(rows:)
    render json: { rows: indices.to_h { |index| [index, rows[index]] } }
  end

  def finalize
    return render(json: { error: "นำเข้าชุดนี้ไปแล้ว" }, status: :unprocessable_entity) if @smart_import.imported?

    @smart_import.assign_attributes(editor_params)
    dataset = build_dataset
    records = @smart_import.rows.map { |row| record_for(row) }.reject { |record| record.except("latitude", "longitude").values.all?(&:blank?) }
    raise ArgumentError, "ไม่มีแถวข้อมูลสำหรับนำเข้า" if records.empty?

    dataset.save!
    begin
      DatasetVersionImportService.new(
        dataset:, user: current_user, manual_records: records, source_kind: "file", allow_missing_location: true,
        source_filename: @smart_import.source_filename, source_content_type: @smart_import.source_content_type,
        source_content: @smart_import.source_file_id && DatasetGridFileStore.download(@smart_import.source_file_id),
        change_note: "นำเข้าอัตโนมัติด้วย AI (#{@smart_import.ai_model}) จาก #{@smart_import.source_filename}"
      ).import!
    rescue StandardError
      dataset.destroy
      raise
    end

    summary = @smart_import.geo_summary
    result = { "dataset_id" => dataset.id.to_s, "dataset_name" => dataset.name, "records" => records.size,
               "located" => records.count { |record| record["latitude"].present? },
               "from_file" => summary["file"] + summary["manual"], "geocoded" => summary["geocoded"],
               "not_found" => summary["not_found"], "outside" => summary["outside"], "no_location" => summary["none"],
               "dataset_url" => imported_dataset_path(dataset), "map_url" => situation_assessment_path }
    DatasetGridFileStore.delete(@smart_import.source_file_id) if @smart_import.source_file_id
    @smart_import.update!(status: "imported", dataset_id: dataset.id, source_file_id: nil, result:, expires_at: 30.days.from_now)
    render json: { result: }
  rescue ArgumentError, Mongoid::Errors::Validations => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def set_smart_import
    @smart_import = SmartImport.find_by(id: params[:id], user_id: current_user.id)
    raise Mongoid::Errors::DocumentNotFound.new(SmartImport, params[:id]) unless @smart_import
  end

  def editor_params
    data = params.permit(:name, columns: %i[key label type role]).to_h
    attributes = {}
    attributes[:name] = data["name"].to_s.strip if data.key?("name")
    attributes[:columns] = Array(data["columns"]).map { |column| column.slice("key", "label", "type", "role") } if data.key?("columns")
    if params[:rows].is_a?(Array) || params[:rows].is_a?(ActionController::Parameters)
      raw = params[:rows].is_a?(Array) ? params[:rows] : params[:rows].values
      attributes[:rows] = raw.first(SmartImport::MAX_ROWS).map do |row|
        row = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
        row.slice(*Array(attributes[:columns] || @smart_import.columns).map { |column| column["key"] }, "latitude", "longitude", "_geo", "_geo_note")
           .transform_values { |value| value.is_a?(String) ? value.tr("๐-๙", "0-9").strip : value }
      end
    end
    attributes
  end

  def build_dataset
    data_columns = @smart_import.data_columns
    raise ArgumentError, "ต้องมีอย่างน้อย 1 คอลัมน์ข้อมูล" if data_columns.empty?
    raise ArgumentError, "มีคอลัมน์ได้ไม่เกิน 48 คอลัมน์" if data_columns.size > 48

    located = @smart_import.located_rows.positive?
    schema = data_columns.each_with_index.map do |column, index|
      { "key" => "field_#{index + 1}", "label" => column["label"].to_s.strip.presence || "คอลัมน์ #{index + 1}",
        "type" => ImportedDataset::FIELD_TYPES.include?(column["type"]) ? column["type"] : "text", "required" => false }
    end
    schema += [{ "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => false },
               { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => false }] if located
    ImportedDataset.new(
      name: @smart_import.name.presence || @smart_import.source_filename, data_type: "custom", user: current_user,
      subdistrict_id: @smart_import.subdistrict_id, shared_with_all: true, schema_definition: schema,
      geometry_type: located ? "point" : "none", map_enabled: located
    )
  end

  def record_for(row)
    record = @smart_import.data_columns.each_with_index.to_h { |column, index| ["field_#{index + 1}", row[column["key"]].to_s.strip] }
    if row["latitude"].present? && row["longitude"].present? && row["_geo"] != "outside"
      record["latitude"] = row["latitude"]
      record["longitude"] = row["longitude"]
    end
    record
  end

  def page_images
    Array(params[:page_images]).first(SmartImports::Extractor::MAX_PAGES).filter_map do |image|
      next unless image.respond_to?(:read) && image.size <= 6.megabytes

      { data: image.read, media_type: image.content_type.presence_in(%w[image/png image/jpeg image/webp]) || "image/jpeg" }
    end
  end

  def llm_for(provider_id, model)
    provider = AiProvider.enabled.where(id: provider_id).first || AiProvider.default_for_chat
    raise ArgumentError, "ยังไม่ได้ตั้งค่าผู้ให้บริการ AI — ผู้ดูแลระบบเพิ่มได้ที่ ตั้งค่าระบบ › ผู้ให้บริการ AI" unless provider

    provider = provider.dup.tap { |copy| copy.model = model.to_s.strip } if model.present?
    [Ai::Llm.for(provider), provider.model]
  end

  def accessible_subdistricts
    scope = current_user.system_admin? ? Subdistrict.all : Subdistrict.where(id: current_user.accessible_subdistrict_ids)
    scope.includes(:province).alphabetical
  end

  def authorize_subdistrict!(subdistrict)
    raise ArgumentError, "กรุณาเลือกพื้นที่ (อบต.) ของข้อมูล" unless subdistrict
    return if current_user.system_admin?
    raise ArgumentError, "เลือกได้เฉพาะพื้นที่ที่รับผิดชอบ" unless current_user.accessible_subdistrict_ids.include?(subdistrict.id)
  end

  def require_importer!
    return if current_user.system_admin? || current_user.subdistrict_admin?

    respond_to do |format|
      format.html { redirect_to data_layers_path, alert: "บัญชีนี้ไม่มีสิทธิ์นำเข้าข้อมูล" }
      format.json { render json: { error: "บัญชีนี้ไม่มีสิทธิ์นำเข้าข้อมูล" }, status: :forbidden }
    end
  end
end

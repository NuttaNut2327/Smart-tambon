class ImportedDatasetsController < ApplicationController
  before_action :require_importer!, except: %i[index show]
  before_action :set_dataset, only: %i[show edit update destroy]
  before_action :authorize_owner!, only: %i[edit update destroy]

  def index
    @datasets = ImportedDataset.visible_to(current_user).where(data_type: "custom").desc(:updated_at).to_a
    @subdistricts = current_user.system_admin? ? Subdistrict.includes(:province).alphabetical : Subdistrict.where(id: current_user.accessible_subdistrict_ids).includes(:province).alphabetical
  end

  def new
    return redirect_to imported_datasets_path if normalized_type == "custom"

    @dataset = ImportedDataset.new(data_type: normalized_type, geometry_type: "none")
    @dataset.schema_definition = ImportedDataset.schema_for(@dataset.data_type) || default_custom_schema
    load_subdistricts
  end

  def create
    @dataset = ImportedDataset.new(dataset_attributes)
    @dataset.user = current_user
    @dataset.shared_with_all = true
    @dataset.schema_definition = schema_definition
    authorize_subdistrict!(@dataset.subdistrict)
    @dataset.save!
    DatasetVersionImportService.new(
      dataset: @dataset, user: current_user, upload: params[:file], manual_records: params[:manual_records],
      change_note: params[:change_note]
    ).import! unless @dataset.data_type == "custom" && params[:file].blank? && params[:manual_records].blank?
    redirect_to(@dataset.data_type == "custom" ? imported_datasets_path : @dataset, notice: "สร้างชุดข้อมูลและ Version 1 เรียบร้อยแล้ว")
  rescue Mongoid::Errors::Validations, ArgumentError => error
    @dataset&.destroy if @dataset&.persisted? && @dataset.current_version_id.blank?
    attributes = @dataset&.attributes&.slice("name", "data_type", "data_category", "geometry_type", "map_enabled", "subdistrict_id") || {}
    definition = @dataset&.schema_definition
    @dataset = ImportedDataset.new(attributes)
    @dataset.schema_definition = definition.presence || ImportedDataset.schema_for(normalized_type) || default_custom_schema
    load_subdistricts
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  def show
    return redirect_to data_layers_path(data_type: @dataset.data_type), notice: "แสดงรายละเอียดชุดข้อมูลในหน้าหลักนำเข้าข้อมูล" unless @dataset.data_type == "custom"
    @versions = @dataset.versions.desc(:version_number).to_a
    respond_to do |format|
      format.html do
        @datasets = ImportedDataset.visible_to(current_user).where(data_type: "custom").desc(:updated_at).to_a
        @subdistricts = current_user.system_admin? ? Subdistrict.includes(:province).alphabetical : Subdistrict.where(id: current_user.accessible_subdistrict_ids).includes(:province).alphabetical
        @selected_dataset = @dataset
        render :index
      end
      format.json do
        render json: {
          id: @dataset.id.to_s, name: @dataset.name, type: @dataset.category_label,
          map_enabled: @dataset.map_enabled?, geometry_type: @dataset.geometry_type,
          schema: @dataset.effective_schema_definition,
          records: Array(@dataset.current_version&.records).first(100),
          record_count: @dataset.record_count,
          current_version_number: @dataset.current_version&.version_number,
          editable: current_user.system_admin? || @dataset.user_id == current_user.id,
          versions: @versions.map { |version|
            {
              id: version.id.to_s, version_number: version.version_number,
              current: @dataset.current_version_id == version.id,
              change_note: version.change_note.presence || (version.source_kind == "manual" ? "เพิ่มหรือแก้ไขข้อมูลด้วยตนเอง" : "นำเข้าข้อมูลจากไฟล์"),
              source_kind: version.source_kind, source_filename: version.source_filename,
              user_name: version.user&.username || "—",
              record_count: version.record_count, created_at: version.created_at.iso8601,
              view_url: imported_dataset_version_path(@dataset, version),
              restore_url: restore_imported_dataset_version_path(@dataset, version),
              downloadable: version.downloadable?,
              download_url: version.downloadable? ? download_imported_dataset_version_path(@dataset, version) : nil
            }
          },
          updated_at: @dataset.updated_at.iso8601
        }
      end
    end
  end

  def edit
    load_subdistricts
  end

  def update
    @dataset.assign_attributes(dataset_attributes.except(:data_type))
    @dataset.schema_definition = schema_definition if params[:schema_definition].present?
    authorize_subdistrict!(@dataset.subdistrict)
    @dataset.save!
    respond_to do |format|
      format.html { redirect_to(@dataset.data_type == "custom" ? imported_datasets_path : data_layers_path(data_type: @dataset.data_type), notice: "อัปเดตการตั้งค่าชุดข้อมูลแล้ว") }
      format.json { render json: { schema: @dataset.effective_schema_definition } }
    end
  rescue Mongoid::Errors::Validations, ArgumentError => error
    respond_to do |format|
      format.html do
        load_subdistricts
        flash.now[:alert] = error.message
        render :edit, status: :unprocessable_entity
      end
      format.json { render json: { error: error.message }, status: :unprocessable_entity }
    end
  end

  def destroy
    @dataset.destroy
    respond_to do |format|
      format.html { redirect_to imported_datasets_path, notice: "ลบชุดข้อมูลและประวัติทุก Version แล้ว" }
      format.json { render json: { redirect_url: imported_datasets_path, message: "ลบชุดข้อมูลเรียบร้อยแล้ว" } }
    end
  end

  private

  def set_dataset
    @dataset = ImportedDataset.visible_to(current_user).find(params[:id])
  end

  def normalized_type
    ImportedDataset::TYPE_LABELS.key?(params[:data_type]) ? params[:data_type] : "custom"
  end

  def dataset_attributes
    params.require(:imported_dataset).permit(:name, :data_type, :data_category, :geometry_type, :map_enabled, :subdistrict_id)
  end

  def schema_definition
    return ImportedDataset.schema_for(@dataset.data_type) if @dataset.data_type != "custom"
    fields = JSON.parse(params[:schema_definition].presence || "[]")
    normalized = fields.each_with_index.map do |field, index|
      key_source = field["key"].presence || field["label"]
      key = key_source.to_s.parameterize(separator: "_").downcase
      key = "field_#{index + 1}" if key.blank?
      { "key" => key,
        "label" => field["label"].to_s.strip, "type" => field["type"].presence || "text",
        "required" => ActiveModel::Type::Boolean.new.cast(field["required"]) }
    end
    if @dataset.geometry_type == "point"
      normalized += [{ "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => true }, { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => true }].reject { |field| normalized.any? { |existing| existing["key"] == field["key"] } }
    end
    normalized
  rescue JSON::ParserError
    raise ArgumentError, "รูปแบบคอลัมน์ไม่ถูกต้อง"
  end

  def default_custom_schema
    [
      { "key" => "name", "label" => "ชื่อรายการ", "type" => "text", "required" => true },
      { "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => false },
      { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => false }
    ]
  end

  def require_importer!
    return if current_user.system_admin? || current_user.subdistrict_admin?
    redirect_to data_layers_path, alert: "บัญชีนี้ไม่มีสิทธิ์นำเข้าหรือแก้ไขข้อมูล"
  end

  def authorize_owner!
    return if current_user.system_admin? || @dataset.user_id == current_user.id
    redirect_to data_layers_path, alert: "ไม่มีสิทธิ์จัดการชุดข้อมูลนี้"
  end

  def authorize_subdistrict!(subdistrict)
    return if current_user.system_admin?
    raise ArgumentError, "กรุณาเลือกพื้นที่ที่รับผิดชอบ" unless subdistrict
    raise ArgumentError, "เลือกได้เฉพาะพื้นที่ที่รับผิดชอบ" unless current_user.accessible_subdistrict_ids.include?(subdistrict.id)
  end

  def load_subdistricts
    @subdistricts = if current_user.system_admin?
      Subdistrict.includes(:province).alphabetical
    else
      Subdistrict.where(id: current_user.accessible_subdistrict_ids).includes(:province).alphabetical
    end
  end
end

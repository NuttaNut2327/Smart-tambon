class ImportedDatasetVersionsController < ApplicationController
  before_action :set_dataset
  before_action :require_owner!, except: %i[show download]
  before_action :set_version, only: %i[show download restore]

  def show
    respond_to do |format|
      format.html { redirect_to dataset_index_path, notice: "แสดงข้อมูล Version ในหน้าหลักนำเข้าข้อมูล" }
      format.json do
        render json: { version_number: @version.version_number, change_note: @version.change_note,
          schema: @dataset.effective_schema_definition, records: @version.records }
      end
    end
  end

  def create
    source_kind = params[:file].present? ? "file" : "manual"
    DatasetVersionImportService.new(dataset: @dataset, user: current_user, upload: params[:file],
      manual_records: params[:manual_records], change_note: params[:change_note], source_kind:,
      append_records: params[:append_records] == "1").import!
    redirect_to dataset_index_path, notice: "สร้าง Version ใหม่เรียบร้อยแล้ว"
  rescue Mongoid::Errors::Validations, ArgumentError => error
    redirect_to dataset_index_path, alert: error.message
  end

  def restore
    version = DatasetVersionImportService.new(dataset: @dataset, user: current_user,
      manual_records: @version.records.deep_dup, change_note: "สร้างจาก Version #{@version.version_number}", source_kind: "restored").import!
    respond_to do |format|
      format.html { redirect_to dataset_index_path, notice: "สร้าง Version ใหม่จาก Version #{@version.version_number} แล้ว" }
      format.json { render json: { version: version.version_number, message: "สร้าง Version ใหม่เรียบร้อยแล้ว" } }
    end
  rescue Mongoid::Errors::Validations, ArgumentError => error
    redirect_to dataset_index_path, alert: error.message
  end

  def download
    return redirect_to(data_layers_path(data_type: @dataset.data_type), alert: "Version นี้ไม่มีไฟล์ต้นฉบับ") unless @version.downloadable?
    send_data DatasetGridFileStore.download(@version.source_file_id), filename: @version.source_filename,
      type: @version.source_content_type.presence || "application/octet-stream", disposition: "attachment"
  end

  private

  def set_dataset
    @dataset = ImportedDataset.visible_to(current_user).find(params[:imported_dataset_id])
  end
  def set_version = @version = @dataset.versions.find(params[:id])
  def dataset_index_path = @dataset.data_type == "custom" ? imported_datasets_path : data_layers_path(data_type: @dataset.data_type)
  def require_owner!
    return if current_user.system_admin? || @dataset.user_id == current_user.id
    redirect_to data_layers_path, alert: "ไม่มีสิทธิ์แก้ไขชุดข้อมูลนี้"
  end
end

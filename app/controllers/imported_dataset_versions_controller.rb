class ImportedDatasetVersionsController < ApplicationController
  before_action :set_dataset
  before_action :require_owner!, except: %i[show download]
  before_action :set_version, only: %i[show update download restore]

  def show
    respond_to do |format|
      format.html do
        @schema = @dataset.effective_schema_definition.reject { |field| field["hidden"] }
        @record_total = @version.record_count.to_i
        @page_size = 50
        @total_pages = [(@record_total.to_f / @page_size).ceil, 1].max
        @page = params[:page].to_i.clamp(1, @total_pages)
        @page_numbers = ([1, @total_pages] + ((@page - 2)..(@page + 2)).to_a).select { |number| number.between?(1, @total_pages) }.uniq.sort
        @records = @version.record_documents.asc(:position).skip((@page - 1) * @page_size).limit(@page_size).pluck(:payload)
        @back_path = dataset_index_path
      end
      format.json do
        if params[:paginated] == "1"
          page_size = 50
          total = @version.record_count.to_i
          total_pages = [(total.to_f / page_size).ceil, 1].max
          page = params[:page].to_i.clamp(1, total_pages)
          records = @version.record_documents.asc(:position).skip((page - 1) * page_size).limit(page_size).pluck(:payload)
          render json: { version_number: @version.version_number, display_name: @version.display_name.presence || @dataset.name,
            change_note: @version.change_note, source_kind: @version.source_kind, created_at: @version.created_at.iso8601,
            schema: @dataset.effective_schema_definition.reject { |field| field["hidden"] }, records: records,
            pagination: { page: page, total_pages: total_pages, total: total, page_size: page_size } }
        else
          render json: { version_number: @version.version_number, display_name: @version.display_name.presence || @dataset.name,
            change_note: @version.change_note,
            schema: @dataset.effective_schema_definition, records: @version.records }
        end
      end
    end
  end

  def create
    source_kind = params[:file].present? ? "file" : "manual"
    version = DatasetVersionImportService.new(dataset: @dataset, user: current_user, upload: params[:file],
      manual_records: params[:manual_records], change_note: params[:change_note], source_kind:,
      append_records: params[:append_records] == "1", display_name: params[:version_name]).import!
    message = source_kind == "file" ? "สร้าง Version #{version.version_number} จากไฟล์เรียบร้อยแล้ว" : "บันทึกข้อมูลใน Version #{version.version_number} เรียบร้อยแล้ว"
    redirect_to dataset_index_path, notice: message
  rescue Mongoid::Errors::Validations, ArgumentError => error
    redirect_to dataset_index_path, alert: error.message
  end

  def update
    display_name = params.require(:imported_dataset_version).permit(:display_name)[:display_name].to_s.strip
    raise ArgumentError, "กรุณาระบุชื่อ Version" if display_name.blank?

    @version.update!(display_name: display_name)
    redirect_to data_layers_path(data_type: @dataset.data_type), notice: "เปลี่ยนชื่อ Version #{@version.version_number} เรียบร้อยแล้ว"
  rescue ActionController::ParameterMissing, Mongoid::Errors::Validations, ArgumentError => error
    redirect_to data_layers_path(data_type: @dataset.data_type), alert: error.message
  end

  def checkpoint
    current_version = @dataset.current_version
    raise ArgumentError, "ยังไม่มีข้อมูลสำหรับบันทึก Snapshot" unless current_version

    version = DatasetVersionImportService.new(dataset: @dataset, user: current_user,
      manual_records: current_version.records.map(&:deep_dup), source_kind: "checkpoint",
      display_name: current_version.display_name.presence || @dataset.name,
      change_note: params[:change_note].presence || "บันทึก Snapshot จาก Version #{current_version.version_number}").import!
    redirect_to dataset_index_path, notice: "บันทึก Snapshot เป็น Version #{version.version_number} เรียบร้อยแล้ว"
  rescue Mongoid::Errors::Validations, ArgumentError => error
    redirect_to dataset_index_path, alert: error.message
  end

  def restore
    version = DatasetVersionImportService.new(dataset: @dataset, user: current_user,
      manual_records: @version.records.deep_dup, change_note: "สร้างจาก Version #{@version.version_number}", source_kind: "restored",
      display_name: @version.display_name.presence || @dataset.name).import!
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
    return if current_user.can_manage_organization_data?(@dataset.user_id)
    redirect_to data_layers_path, alert: "ไม่มีสิทธิ์แก้ไขชุดข้อมูลนี้"
  end
end

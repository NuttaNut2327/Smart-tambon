class ImportedDatasetRecordsController < ApplicationController
  before_action :set_dataset

  def update
    records = current_records
    records.fetch(position)
    updated_record = record_params
    if @dataset.data_type == "incidents"
      updated_record["reference_code"] = records[position]["reference_code"]
      updated_record["status"] = records[position]["status"]
    end
    records[position] = updated_record
    version = create_version(records, "แก้ไข#{@dataset.type_label}")
    render json: success_payload(version)
  rescue IndexError
    render json: { error: "ไม่พบข้อมูลที่ต้องการแก้ไข" }, status: :not_found
  rescue ActionController::ParameterMissing, Mongoid::Errors::Validations, ArgumentError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def destroy
    records = current_records
    records.delete_at(position) || raise(IndexError)
    version = create_version(records, "ลบ#{@dataset.type_label}")
    render json: success_payload(version)
  rescue IndexError
    render json: { error: "ไม่พบข้อมูลที่ต้องการลบ" }, status: :not_found
  rescue Mongoid::Errors::Validations, ArgumentError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def set_dataset
    scope = current_user.system_admin? ? ImportedDataset.all : ImportedDataset.where(user_id: current_user.id)
    @dataset = scope.where(id: params[:imported_dataset_id], data_type: { "$in" => ImportedDataset::TYPE_LABELS.keys }).first
    return if @dataset
    render json: { error: "ไม่พบชุดข้อมูล หรือคุณไม่มีสิทธิ์แก้ไข" }, status: :not_found
  end

  def position
    Integer(params[:id], 10)
  rescue ArgumentError
    raise IndexError
  end

  def current_records
    Array(@dataset.current_version&.records).map(&:deep_dup)
  end

  def record_params
    keys = @dataset.effective_schema_definition.reject do |field|
      field["generated"] || (@dataset.data_type == "incidents" && %w[reference_code status].include?(field["key"]))
    end.map { |field| field["key"] }
    params.require(:record).permit(*keys).to_h
  end

  def create_version(records, default_note)
    DatasetVersionImportService.new(dataset: @dataset, user: current_user, manual_records: records,
      source_kind: "manual", change_note: params[:change_note].presence || default_note, allow_empty: true).import!
  end

  def success_payload(version)
    { version: version.version_number, records: version.record_count,
      redirect_url: data_layers_path(data_type: @dataset.data_type) }
  end
end

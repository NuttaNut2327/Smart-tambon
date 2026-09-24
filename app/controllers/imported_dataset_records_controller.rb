class ImportedDatasetRecordsController < ApplicationController
  before_action :set_dataset

  def update
    records = current_records
    records.fetch(position)
    updated_record = record_params
    @dataset.effective_schema_definition.select { |field| field["generated"] }.each do |field|
      updated_record[field["key"]] = records[position][field["key"]] if records[position][field["key"]].present?
    end
    if @dataset.data_type == "incidents"
      updated_record["reference_code"] = records[position]["reference_code"]
      updated_record["status"] = records[position]["status"]
    elsif @dataset.data_type == "population"
      %w[boundary_status boundary_dataset_id boundary_record_position].each do |key|
        updated_record[key] = records[position][key] if records[position][key].present?
      end
    elsif @dataset.data_type == "village_boundaries"
      updated_record["boundary_source"] = params.dig(:record, :boundary_source).presence || records[position]["boundary_source"]
    elsif @dataset.data_type == "consumables"
      # ยอดคงเหลือต้องเปลี่ยนผ่านรายการรับเข้า–เบิกออก เพื่อให้ตรวจสอบย้อนหลังได้เสมอ
      updated_record["current_quantity"] = records[position]["current_quantity"]
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
    scope = if current_user.system_admin?
              ImportedDataset.all
            elsif current_user.subdistrict_admin?
              ImportedDataset.any_of(
                { user_id: current_user.id },
                { shared_with_all: true, subdistrict_id: { "$in" => current_user.accessible_subdistrict_ids } }
              )
            else
              ImportedDataset.where(user_id: current_user.id)
            end
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

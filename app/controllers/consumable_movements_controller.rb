class ConsumableMovementsController < ApplicationController
  def create
    dataset = editable_datasets.where(id: params[:imported_dataset_id], data_type: "consumables").first
    raise ArgumentError, "ไม่พบชุดข้อมูลวัสดุสิ้นเปลือง" unless dataset

    movement_type = params.require(:movement_type).to_s
    result = ConsumableStockMovementService.new(dataset: dataset, record_position: params.require(:record_position),
      movement_type: movement_type, quantity: params.require(:quantity), user: current_user,
      incident_reference: params[:incident_reference], note: params[:note]).call

    redirect_to data_layers_path(data_type: "consumables"), notice: "บันทึก#{movement_label(movement_type)}เรียบร้อยแล้ว · คงเหลือ #{result.quantity_after.to_fs(:delimited)} #{result.unit}"
  rescue ActionController::ParameterMissing, ArgumentError, Mongoid::Errors::Validations => error
    redirect_to data_layers_path(data_type: "consumables"), alert: error.message
  end

  private

  def editable_datasets
    return ImportedDataset.all if current_user.system_admin?

    return ImportedDataset.where(user_id: current_user.id) unless current_user.subdistrict_admin?

    ImportedDataset.any_of(
      { user_id: current_user.id },
      { shared_with_all: true, subdistrict_id: { "$in" => current_user.accessible_subdistrict_ids } }
    )
  end

  def movement_label(type)
    { "receive" => "รับเข้า", "issue" => "เบิกออก", "return" => "คืนเข้า", "adjustment" => "ปรับยอด" }.fetch(type)
  end
end

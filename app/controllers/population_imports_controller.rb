class PopulationImportsController < ApplicationController
  def create
    return redirect_to data_layers_path, alert: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำตำบลเท่านั้นที่นำเข้าข้อมูลได้" unless current_user.system_admin? || current_user.subdistrict_admin?
    return redirect_to data_layers_path, alert: "หัวข้อข้อมูลที่เลือกยังไม่รองรับ" unless params[:data_type] == "population"

    dataset = PopulationImportService.new(upload: params[:file], user: current_user).import!
    redirect_to population_dashboard_path(dataset), notice: "นำเข้าข้อมูลประชากรเรียบร้อยแล้ว"
  rescue ArgumentError, Roo::Error => error
    redirect_to data_layers_path, alert: error.message
  end
end

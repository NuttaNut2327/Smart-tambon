class PopulationDashboardsController < ApplicationController
  def show
    @dataset = PopulationDataset.includes(:subdistrict).find(params[:id])
    return redirect_to root_path, alert: "ไม่มีสิทธิ์เข้าถึงข้อมูลนี้" unless PopulationDataset.visible_to(current_user).exists?(id: @dataset.id)
  end
end

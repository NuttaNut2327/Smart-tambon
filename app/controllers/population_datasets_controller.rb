class PopulationDatasetsController < ApplicationController
  def destroy
    dataset = PopulationDataset.find(params[:id])
    unless current_user.system_admin? || dataset.user_id == current_user.id
      return redirect_to data_layers_path, alert: "ไม่มีสิทธิ์ลบชุดข้อมูลนี้"
    end

    dataset.destroy!
    redirect_to data_layers_path, notice: "ลบชุดข้อมูลและ Dashboard ที่เกี่ยวข้องแล้ว"
  end
end

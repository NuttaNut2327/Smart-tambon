class MyAccessAreasController < ApplicationController
  before_action :require_subdistrict_admin!

  def update
    name = access_area_params[:name].to_s.strip
    raise ArgumentError, "กรุณาระบุชื่อขอบเขตพื้นที่ดูแล" if name.blank?

    area = current_user.access_area || UserAccessAreaService.new(user: current_user, name: name, subdistrict_ids: [current_user.subdistrict_id], boundary_file: nil).save!
    area.update!(name: name)
    redirect_to root_path, notice: "อัปเดตชื่อขอบเขตพื้นที่ดูแลเรียบร้อยแล้ว"
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end

  private

  def access_area_params
    params.fetch(:access_area, {}).permit(:name)
  end

  def require_subdistrict_admin!
    return if current_user.subdistrict_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลประจำตำบลเท่านั้นที่แก้ไขขอบเขตพื้นที่ได้"
  end
end

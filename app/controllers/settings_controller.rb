# /settings sends each admin to the settings they manage.
class SettingsController < ApplicationController
  def index
    return redirect_to system_settings_path if system_admin?
    return redirect_to organization_settings_path if current_user.subdistrict_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำ อบต. เท่านั้นที่เข้าถึงการตั้งค่าได้"
  end
end

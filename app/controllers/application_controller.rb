class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :require_access_configuration!

  helper_method :system_admin?, :global_viewer?

  private

  def system_admin?
    current_user.system_admin?
  end

  def global_viewer?
    current_user.system_admin?
  end

  def require_access_configuration!
    return unless user_signed_in?
    return if current_user&.system_admin? || current_user&.subdistrict.present? || current_user&.access_area.present?

    sign_out current_user
    redirect_to new_user_session_path, alert: "บัญชีนี้ยังไม่ได้กำหนด role หรือขอบเขตพื้นที่ดูแล"
  end

  def authorized_for_subdistrict?(subdistrict)
    global_viewer? || current_user.accessible_subdistrict_ids.include?(subdistrict.id)
  end

  def render_forbidden
    render json: { error: "ไม่มีสิทธิ์เข้าถึงข้อมูลนี้" }, status: :forbidden
  end

  def require_system_admin!
    return if system_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่จัดการผู้ใช้ได้"
  end
end

class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :normalize_authentication_flash!
  before_action :require_access_configuration!

  helper_method :system_admin?, :global_viewer?, :user_manager?, :announcement_feed

  private

  def normalize_authentication_flash!
    already_authenticated_messages = [
      "You are already signed in.",
      I18n.t("devise.failure.already_authenticated", default: "คุณเข้าสู่ระบบแล้ว")
    ]
    return unless already_authenticated_messages.include?(flash[:alert])

    flash[:notice] = "คุณเข้าสู่ระบบแล้ว"
    flash.delete(:alert)
  end

  # Popup announcements for the layout; nil on login, public and non-HTML pages.
  def announcement_feed
    return @announcement_feed if defined?(@announcement_feed)

    @announcement_feed = (AnnouncementFeed.new(current_user, session) if show_announcements?)
  end

  def show_announcements?
    user_signed_in? && !devise_controller? && request.format.html?
  end

  def system_admin?
    current_user.system_admin?
  end

  def global_viewer?
    current_user.system_admin?
  end

  def user_manager?
    current_user.system_admin? || current_user.subdistrict_admin?
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

  def require_user_manager!
    return if user_manager?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำ อบต. เท่านั้นที่จัดการผู้ใช้ได้"
  end
end

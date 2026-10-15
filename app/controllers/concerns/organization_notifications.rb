# Shared by the อบต. notification pages: only admins manage them, and everything is keyed by the account's
# organisation so each อบต. sees only its own channels, templates and delivery log.
module OrganizationNotifications
  extend ActiveSupport::Concern

  included do
    before_action :require_notification_manager!
    helper_method :organization_key
  end

  private

  def organization_key = current_user.organization_key

  def require_notification_manager!
    return if system_admin? || current_user.subdistrict_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลประจำ อบต. เท่านั้นที่ตั้งค่าการแจ้งเตือนได้"
  end
end

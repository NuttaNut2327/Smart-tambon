module Admin
  # System-admin-only pages. While switched into an อบต. account the real admin is not current_user, so these
  # pages are unavailable until they switch back.
  class BaseController < ApplicationController
    before_action :require_system_admin_access!

    private

    def require_system_admin_access!
      return if system_admin?

      redirect_to root_path, alert: session[:impersonator_id] ? "กลับเป็นผู้ดูแลระบบก่อน (แถบด้านบน) จึงจะเข้าหน้านี้ได้" : "เฉพาะผู้ดูแลระบบเท่านั้น"
    end
  end
end

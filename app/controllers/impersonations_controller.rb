# "กลับเป็นผู้ดูแลระบบ": end a switched-into session and sign the original system admin back in.
class ImpersonationsController < ApplicationController
  skip_before_action :require_access_configuration!

  def destroy
    admin = session[:impersonator_id] && User.find_by(id: session[:impersonator_id], role: User.roles[:system_admin])
    return redirect_to(root_path) unless admin

    from = current_user
    session.delete(:impersonator_id)
    sign_in(:user, admin)
    AdminAuditLog.record!(admin, "switch_back", from.organization_key, request:, from_user_id: from.id)
    redirect_to admin_organizations_path, notice: "กลับเป็นผู้ดูแลระบบแล้ว"
  end
end

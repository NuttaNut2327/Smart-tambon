module Admin
  # Review queue for self-registered organisations.
  class RegistrationsController < BaseController
    before_action :set_registration, only: %i[show approve reject]

    def index
      @status = OrganizationRegistration::STATUSES.key?(params[:status]) ? params[:status] : "pending_review"
      @counts = OrganizationRegistration.where(:status.ne => "draft").group_by(&:status).transform_values(&:size)
      @registrations = OrganizationRegistration.where(status: @status).order_by(submitted_at: :desc, created_at: :desc).limit(200).to_a
    end

    def show; end

    def approve
      user = Registrations::Approval.approve!(@registration, current_user)
      AdminAuditLog.record!(current_user, "approve_registration", user.organization_key, request:, registration_id: @registration.id.to_s, username: user.username)
      redirect_to admin_registrations_path, notice: "อนุมัติ #{@registration.organization_name} แล้ว — สร้างบัญชี #{user.username} เรียบร้อย"
    rescue Registrations::Approval::Error => error
      redirect_to admin_registration_path(@registration), alert: error.message
    end

    def reject
      return redirect_to(admin_registration_path(@registration), alert: "คำขอนี้ไม่ได้อยู่ในสถานะรออนุมัติ") unless @registration.status == "pending_review"

      Registrations::Approval.reject!(@registration, current_user, params[:reason])
      AdminAuditLog.record!(current_user, "reject_registration", "registration:#{@registration.id}", request:, reason: params[:reason].to_s.truncate(200))
      redirect_to admin_registrations_path, notice: "ไม่อนุมัติคำขอของ #{@registration.organization_name}"
    end

    private

    def set_registration
      @registration = OrganizationRegistration.where(:status.ne => "draft").find(params[:id])
    rescue Mongoid::Errors::DocumentNotFound
      redirect_to admin_registrations_path, alert: "ไม่พบคำขอ"
    end
  end
end

module Registrations
  # Turns an approved application into a working อบต. account: the admin user (with the password hash the applicant
  # set), the organisation settings, and an access area when the organisation is not a plain อบต.
  class Approval
    class Error < StandardError; end

    def self.approve!(registration, reviewer) = new(registration, reviewer).approve!

    def self.reject!(registration, reviewer, reason)
      registration.set(status: "rejected", reviewed_by: reviewer.username, reviewed_at: Time.current, reject_reason: reason.to_s.strip.truncate(500).presence)
      notify(registration)
    end

    def self.notify(registration)
      RegistrationMailer.reviewed(registration).deliver_now if ENV["SMTP_ADDRESS"].present? && registration.email.present?
    rescue StandardError => error
      Rails.logger.warn("Registration notification failed: #{error.class}: #{error.message}")
    end

    def initialize(registration, reviewer)
      @registration = registration
      @reviewer = reviewer
    end

    def approve!
      raise Error, "คำขอนี้ไม่ได้อยู่ในสถานะรออนุมัติ" unless @registration.status == "pending_review"
      raise Error, "ตำบลนี้มีผู้ดูแลในระบบแล้ว" if OrganizationRegistration.area_status(@registration.subdistrict_id, except: @registration.id) == "taken"

      user = nil
      User.transaction do
        user = User.new(username: @registration.username, email: @registration.email, phone: @registration.phone,
                        full_name: @registration.admin_full_name, position: @registration.admin_position,
                        role: :subdistrict_admin, subdistrict_id: @registration.subdistrict_id)
        # The applicant's own password, already hashed by Devise at the account step.
        user.encrypted_password = @registration.password_digest
        user.define_singleton_method(:password_required?) { false }
        user.save!
        create_access_area(user) unless @registration.organization_type == "subdistrict_administrative_organization"
      end
      setting = OrganizationSetting.find_or_create_by!(organization_key: user.organization_key)
      setting.update!(organization_name: @registration.organization_name, phone: @registration.office_phone,
                      address: @registration.address, email: @registration.email, updated_by: @reviewer.username)
      @registration.set(status: "approved", user_id: user.id, reviewed_by: @reviewer.username, reviewed_at: Time.current, reject_reason: nil)
      self.class.notify(@registration)
      user
    rescue ActiveRecord::RecordInvalid => error
      raise Error, "สร้างบัญชีไม่สำเร็จ: #{error.record.errors.full_messages.to_sentence}"
    end

    private

    def create_access_area(user)
      subdistrict = Subdistrict.find(@registration.subdistrict_id)
      UserAccessArea.create!(user:, name: @registration.organization_name, source: "subdistricts", subdistrict_ids: [subdistrict.id],
                             boundary: subdistrict.boundary, organization_type: @registration.organization_type)
    end
  end
end

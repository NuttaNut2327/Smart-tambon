# Emails for the อบต. self-registration: the OTP code and the review result.
class RegistrationMailer < ApplicationMailer
  def otp(registration, code)
    @registration = registration
    @code = code
    mail to: registration.otp_target, subject: "รหัสยืนยันการลงทะเบียน #{code}"
  end

  def reviewed(registration)
    @registration = registration
    @login_url = new_user_session_url
    subject = registration.status == "approved" ? "อนุมัติการลงทะเบียนแล้ว" : "ผลการพิจารณาการลงทะเบียน"
    mail to: registration.email, subject:
  end
end

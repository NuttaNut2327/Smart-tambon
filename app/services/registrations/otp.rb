module Registrations
  # One-time passwords for the registration wizard. Email codes are generated here and only their HMAC is stored;
  # SMS codes use smsmkt's OTP service (it generates, sends and validates the code; we keep its token).
  class Otp
    class Error < StandardError; end

    TTL = 10.minutes
    RESEND_AFTER = 60.seconds
    MAX_SENDS = 5
    MAX_ATTEMPTS = 5

    def self.sms_available? = SmsSetting.current.secret("otp_project_key").present? && SmsSetting.current.secret("sms_api_key").present?
    def self.email_available? = ENV["SMTP_ADDRESS"].present? || Rails.env.development?

    def initialize(registration)
      @registration = registration
    end

    def deliver(channel)
      raise Error, "เลือกช่องทางรับรหัสให้ถูกต้อง" unless OrganizationRegistration::OTP_CHANNELS.key?(channel)
      raise Error, "ส่งรหัสครบ #{MAX_SENDS} ครั้งแล้ว กรุณาเริ่มลงทะเบียนใหม่หรือติดต่อผู้ดูแลระบบ" if @registration.otp_sends >= MAX_SENDS
      wait = @registration.otp_last_sent_at && (@registration.otp_last_sent_at + RESEND_AFTER - Time.current).ceil
      raise Error, "กรุณารอ #{wait} วินาทีก่อนขอรหัสใหม่" if wait&.positive?

      channel == "sms" ? deliver_sms : deliver_email
      @registration.inc(otp_sends: 1)
      @registration.set(otp_channel: channel, otp_attempts: 0, otp_last_sent_at: Time.current, otp_expires_at: Time.current + TTL)
    end

    def verify!(code)
      code = code.to_s.gsub(/\D/, "")
      raise Error, "ยังไม่ได้ขอรหัสยืนยัน" if @registration.otp_expires_at.blank?
      raise Error, "รหัสหมดอายุแล้ว กรุณาขอรหัสใหม่" if @registration.otp_expires_at.past?
      raise Error, "กรอกรหัสผิดเกิน #{MAX_ATTEMPTS} ครั้ง กรุณาขอรหัสใหม่" if @registration.otp_attempts >= MAX_ATTEMPTS
      raise Error, "กรุณากรอกรหัส 4–8 หลัก" unless code.length.between?(4, 8)

      @registration.inc(otp_attempts: 1)
      valid = @registration.otp_channel == "sms" ? valid_sms?(code) : valid_email?(code)
      raise Error, "รหัสไม่ถูกต้อง (เหลืออีก #{MAX_ATTEMPTS - @registration.otp_attempts} ครั้ง)" unless valid

      @registration.set(verified_at: Time.current, otp_code_digest: nil, otp_provider_token: nil, otp_expires_at: nil)
    end

    private

    def deliver_email
      raise Error, "ระบบยังไม่ได้ตั้งค่าการส่งอีเมล กรุณาเลือกรับรหัสทาง SMS" unless self.class.email_available?

      code = format("%06d", SecureRandom.random_number(1_000_000))
      @registration.set(otp_target: @registration.email, otp_code_digest: digest(code), otp_ref: SecureRandom.alphanumeric(4).upcase, otp_provider_token: nil)
      if ENV["SMTP_ADDRESS"].present?
        RegistrationMailer.otp(@registration, code).deliver_now
      else
        # Development without SMTP: the code is only written to the development log.
        Rails.logger.info("[registration-otp] #{@registration.email} code=#{code} ref=#{@registration.otp_ref}")
      end
    rescue Net::SMTPError, SocketError, SystemCallError, Timeout::Error => error
      raise Error, "ส่งอีเมลไม่สำเร็จ: #{error.message.truncate(100)}"
    end

    def deliver_sms
      raise Error, "ระบบยังไม่ได้ตั้งค่า SMS OTP กรุณาเลือกรับรหัสทางอีเมล" unless self.class.sms_available?

      result = Sms::SmsmktClient.new.otp_send(phone: @registration.phone)
      raise Error, "ส่ง SMS ไม่สำเร็จ: #{result.error}" unless result.ok?

      payload = result.body["result"].is_a?(Hash) ? result.body["result"] : result.body
      raise Error, "ส่ง SMS ไม่สำเร็จ: ไม่ได้รับ token จาก smsmkt" if payload["token"].blank?

      @registration.set(otp_target: @registration.phone, otp_provider_token: payload["token"], otp_ref: payload["ref_code"], otp_code_digest: nil)
    end

    def valid_email?(code)
      @registration.otp_code_digest.present? && ActiveSupport::SecurityUtils.secure_compare(@registration.otp_code_digest, digest(code))
    end

    def valid_sms?(code)
      result = Sms::SmsmktClient.new.otp_validate(token: @registration.otp_provider_token, otp_code: code, ref_code: @registration.otp_ref)
      payload = result.body["result"].is_a?(Hash) ? result.body["result"] : {}
      result.ok? && payload["status"] != false
    end

    def digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{@registration.token}:#{code}")
  end
end

# System admin: smsmkt credentials, sender name, message templates and link host, plus test tools for a plain
# SMS and the OTP send/validate pair.
class SmsSettingsController < ApplicationController
  before_action :require_system_admin_for_sms!
  before_action :set_setting

  def show
    @recent = SmsMessage.desc(:created_at).limit(20).to_a
  end

  def update
    @setting.assign_attributes(setting_params)
    %w[sms_api_key sms_secret_key otp_project_key].each do |name|
      @setting.public_send(:"assign_#{name}", params.dig(:sms_setting, name), clear: params.dig(:sms_setting, "clear_#{name}") == "1")
    end
    @setting.updated_by = current_user.username
    if @setting.save
      redirect_to sms_settings_path, notice: "บันทึกการตั้งค่า SMS แล้ว"
    else
      show
      render :show, status: :unprocessable_entity
    end
  end

  # A real SMS using the normal template, linking to the public tracking page host.
  def test_message
    phone = Sms::PhoneNumber.normalize(params[:phone])
    return redirect_to(sms_settings_path, alert: "เบอร์ต้องเป็นมือถือไทย 10 หลัก") unless phone
    return redirect_to(sms_settings_path, alert: "ยังไม่ได้ตั้งค่า sms_sender") if @setting.sms_sender.blank?

    message = "[ทดสอบ] #{@setting.sms_msg.gsub(/\{\{\s*[a-z_]+\s*\}\}/, '')}".squeeze(" ")
    link = @setting.effective_host_url || "https://example.com"
    result = Sms::SmsmktClient.new(@setting).send_message(phone: phone, message: message, url: link)
    audit("test", phone, message, link, result)
    redirect_to sms_settings_path, **(result.ok? ? { notice: "ส่ง SMS ทดสอบถึง #{phone} แล้ว" } : { alert: "ส่งไม่สำเร็จ: #{result.error}" })
  end

  def otp_send
    phone = Sms::PhoneNumber.normalize(params[:phone])
    return redirect_to(sms_settings_path, alert: "เบอร์ต้องเป็นมือถือไทย 10 หลัก") unless phone

    result = Sms::SmsmktClient.new(@setting).otp_send(phone: phone)
    audit("otp", phone, "OTP", nil, result)
    if result.ok?
      session[:sms_otp_test] = { "token" => result.body.dig("result", "token"), "ref_code" => result.body.dig("result", "ref_code").to_s, "phone" => phone }
      redirect_to sms_settings_path(anchor: "otp"), notice: "ส่ง OTP ถึง #{phone} แล้ว (ref #{session[:sms_otp_test]['ref_code']}) — กรอกรหัสที่ได้รับเพื่อตรวจสอบ"
    else
      redirect_to sms_settings_path(anchor: "otp"), alert: "ส่ง OTP ไม่สำเร็จ: #{result.error}"
    end
  end

  def otp_validate
    pending = session[:sms_otp_test]
    return redirect_to(sms_settings_path(anchor: "otp"), alert: "ยังไม่มี OTP ที่รอตรวจสอบ") unless pending

    result = Sms::SmsmktClient.new(@setting).otp_validate(token: pending["token"], otp_code: params[:otp_code].to_s.strip, ref_code: pending["ref_code"])
    valid = result.ok? && result.body.dig("result", "status") == true
    session.delete(:sms_otp_test) if valid
    redirect_to sms_settings_path(anchor: "otp"), **(valid ? { notice: "รหัส OTP ถูกต้อง" } : { alert: "รหัส OTP ไม่ถูกต้อง#{": #{result.error}" if result.error}" })
  end

  private

  def set_setting = @setting = SmsSetting.current

  def setting_params
    params.require(:sms_setting).permit(:enabled, :sms_sender, :sms_msg, :sms_video_msg, :host_url, :video_enabled, :video_base_url, :cooldown_seconds)
  end

  def audit(kind, phone, message, link, result)
    SmsMessage.create!(kind: kind, phone: phone, message: message, link: link, sender: @setting.sms_sender, status: result.ok? ? "SENT" : "FAIL",
                       http_status: result.http_status, provider_code: result.code, provider_response: kind == "otp" ? result.body.except("result") : result.body,
                       error: result.error, sent_by: current_user.username, organization_key: current_user.organization_key)
  end

  def require_system_admin_for_sms!
    return if system_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่ตั้งค่า SMS ได้"
  end
end

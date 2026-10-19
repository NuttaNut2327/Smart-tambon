module Sms
  # Sends the reporter of an incident an SMS with a link (tracking page, or a video room when enabled).
  # Unlike SmartEMS, the incident's SENT/FAIL status follows the provider's real answer, and every attempt is
  # audited with the exact message, link and response.
  class IncidentLinkSender
    class Error < StandardError; end

    Preview = Struct.new(:mode, :phone, :link, :template, keyword_init: true)

    def initialize(incident:, user:, setting: SmsSetting.current, client: nil)
      @incident = incident
      @user = user
      @setting = setting
      @client = client || SmsmktClient.new(setting)
    end

    # Unknown or unavailable modes fall back to tracking, never an error.
    def self.mode_for(value, setting = SmsSetting.current) = setting.modes.key?(value.to_s) ? value.to_s : "tracking"

    def preview(mode)
      mode = self.class.mode_for(mode, @setting)
      Preview.new(mode: mode, phone: PhoneNumber.normalize(@incident.reporter_contact), link: link_for(mode),
                  template: render(mode == "video" ? @setting.sms_video_msg : @setting.sms_msg))
    end

    def deliver(mode)
      preview = preview(mode)
      raise Error, "ระบบ SMS ยังไม่พร้อม — ผู้ดูแลระบบต้องตั้งค่า api_key, secret_key และชื่อผู้ส่ง" unless @setting.ready?
      raise Error, "ไม่มีเบอร์ติดต่อของผู้แจ้ง หรือเบอร์ไม่ใช่มือถือไทย (#{@incident.reporter_contact.presence || 'ว่าง'})" if preview.phone.blank?
      raise Error, "ยังไม่ได้ตั้งค่า host_url สำหรับประกอบลิงก์" if @setting.effective_host_url.blank?
      if (wait = cooldown_remaining).positive?
        raise Error, "เพิ่งส่ง SMS เรื่องนี้ไป กรุณารออีก #{wait} วินาที"
      end

      result = @client.send_message(phone: preview.phone, message: preview.template, url: preview.link)
      record(preview, result)
      [preview, result]
    end

    private

    def cooldown_remaining
      last = SmsMessage.where(incident_id: @incident.id, kind: "link").desc(:created_at).first
      return 0 unless last

      (@setting.cooldown_seconds - (Time.current - last.created_at)).ceil.clamp(0, @setting.cooldown_seconds)
    end

    # The token/room is created on first use and reused afterwards, so the preview shows the exact link that is sent.
    def link_for(mode)
      base = @setting.effective_host_url
      if mode == "video"
        room = @incident.video_room.presence || "smarttambon-#{@incident.reference_code.to_s.downcase}-#{SecureRandom.hex(4)}"
        @incident.set(video_room: room) if @incident.video_room.blank?
        "#{@setting.video_base_url}/#{room}"
      else
        token = @incident.tracking_token.presence || SecureRandom.urlsafe_base64(18)
        @incident.set(tracking_token: token) if @incident.tracking_token.blank?
        base ? "#{base}/t/#{token}" : nil
      end
    end

    def render(template)
      organization = OrganizationSetting.where(organization_key: User.where(id: @incident.owner_user_id).pick(:organization_key)).pick(:organization_name)
      values = { "organization_name" => organization || "อบต.", "reference_code" => @incident.reference_code,
                 "title" => @incident.title.to_s.truncate(60), "system_name" => SystemSetting.current.system_short_name }
      template.to_s.gsub(/\{\{\s*([a-z_]+)\s*\}\}/) { values[Regexp.last_match(1)].to_s }
    end

    def record(preview, result)
      status = result.ok? ? "SENT" : "FAIL"
      SmsMessage.create!(kind: "link", incident_id: @incident.id, organization_key: @user.organization_key, mode: preview.mode,
                         phone: preview.phone, message: preview.template, link: preview.link, sender: @setting.sms_sender,
                         status: status, http_status: result.http_status, provider_code: result.code,
                         provider_response: result.body, error: result.error, sent_by: @user.username)
      @incident.histories << {
        "title" => result.ok? ? "ส่ง SMS ถึงผู้แจ้ง (#{@setting.modes[preview.mode]})" : "ส่ง SMS ถึงผู้แจ้งไม่สำเร็จ",
        "description" => [ "เบอร์ #{preview.phone}", ("ข้อผิดพลาด: #{result.error}" unless result.ok?) ].compact.join(" · "),
        "occurred_at" => Time.current.utc.iso8601, "actor" => @user.username, "kind" => "sms"
      }
      @incident.sms_status = status
      @incident.sms_error = result.error
      @incident.sms_sent_at = Time.current if result.ok?
      @incident.save!(validate: false)
    end
  end
end

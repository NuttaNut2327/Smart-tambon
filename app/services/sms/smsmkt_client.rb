module Sms
  # smsmkt HTTP API (https://developers.smsmkt.com/en/api-reference). Credentials go in the api_key / secret_key
  # headers. TLS is verified (the SmartEMS client disabled it); requests time out, and a request is retried once
  # only when the connection could not be opened, so a message is never sent twice.
  class SmsmktClient
    BASE_URL = "https://portal-otp.smsmkt.com/api".freeze
    OK_CODE = "000".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    Result = Struct.new(:ok, :http_status, :code, :detail, :body, :error, keyword_init: true) do
      def ok? = ok
    end

    CODE_MESSAGES = {
      "100" => "ข้อมูลที่ส่งไม่ครบ", "107" => "เบอร์โทรไม่ถูกต้อง", "108" => "ลิงก์ (url) ไม่ถูกต้อง", "110" => "เบอร์นี้อยู่ในบัญชีดำ (blacklist)",
      "300" => "ไม่พบชื่อผู้ส่ง (sender) — ต้องจดทะเบียนกับ smsmkt ก่อน", "400" => "เครดิต SMS ไม่พอ", "500" => "บัญชี smsmkt หมดอายุ",
      "1000" => "ข้อความมีอักขระพิเศษที่ส่งไม่ได้", "1003" => "ข้อความไม่มีแท็ก <TRACKING-URL>", "1004" => "api_key หรือ secret_key ไม่ถูกต้อง",
      "1005" => "ไม่พบ project_key ของ OTP", "1006" => "ไม่พบ token ของ OTP", "1007" => "ไม่มีสิทธิ์ใช้งาน (ตรวจชื่อผู้ส่ง/IP/สิทธิ์ API)",
      "5000" => "token ของ OTP หมดอายุ", "9999" => "ผู้ให้บริการขัดข้อง กรุณาลองใหม่"
    }.freeze

    def initialize(setting = SmsSetting.current, base_url: BASE_URL)
      @setting = setting
      @base_url = base_url
    end

    # message must contain <TRACKING-URL>; smsmkt replaces it with a shortened form of url.
    def send_message(phone:, message:, url: nil, sender: @setting.sms_sender)
      post("send-message", { message: message, sender: sender, phone: phone, url: url }.compact)
    end

    def otp_send(phone:, ref_code: nil)
      project_key = @setting.secret("otp_project_key")
      return failure("ยังไม่ได้ตั้งค่า project_key ของ OTP") if project_key.blank?

      post("otp-send", { project_key: project_key, phone: phone, ref_code: ref_code }.compact)
    end

    def otp_validate(token:, otp_code:, ref_code: nil)
      post("otp-validate", { token: token, otp_code: otp_code, ref_code: ref_code }.compact)
    end

    private

    def post(path, body)
      api_key = @setting.secret("sms_api_key")
      secret_key = @setting.secret("sms_secret_key")
      return failure("ยังไม่ได้ตั้งค่า sms_api_key / sms_secret_key") if api_key.blank? || secret_key.blank?

      uri = URI.parse("#{@base_url}/#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["api_key"] = api_key
      request["secret_key"] = secret_key
      request.body = body.to_json
      response = with_open_retry { Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) } }
      parse(response)
    rescue Net::ReadTimeout
      failure("ผู้ให้บริการตอบช้าเกิน #{READ_TIMEOUT} วินาที — ข้อความอาจถูกส่งแล้ว ตรวจสอบก่อนส่งซ้ำ")
    rescue Net::OpenTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
      failure("เชื่อมต่อ smsmkt ไม่ได้: #{error.message.truncate(120)}")
    end

    def with_open_retry
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Net::OpenTimeout, Errno::ECONNREFUSED, SocketError
        retry if attempts < 2
        raise
      end
    end

    def parse(response)
      body = JSON.parse(response.body.presence || "{}") rescue { "raw" => response.body.to_s.truncate(1000) }
      body = { "raw" => body } unless body.is_a?(Hash)
      code = body["code"]&.to_s
      ok = response.is_a?(Net::HTTPSuccess) && (code.nil? || code == OK_CODE)
      error = ok ? nil : (CODE_MESSAGES[code&.split("-")&.first] || body["detail"].presence || "HTTP #{response.code}")
      Result.new(ok: ok, http_status: response.code.to_s, code: code, detail: body["detail"], body: body, error: error && [error, code && "(code #{code})"].compact.join(" "))
    end

    def failure(message) = Result.new(ok: false, http_status: nil, code: nil, detail: nil, body: {}, error: message)
  end
end

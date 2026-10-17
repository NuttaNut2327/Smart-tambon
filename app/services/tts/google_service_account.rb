require "net/http"
require "base64"

module Tts
  # OAuth2 for Google Cloud with a service account key file (the JSON downloaded from IAM › Service accounts › Keys):
  # signs a JWT with the account's private key and swaps it for a one-hour access token, cached per account.
  module GoogleServiceAccount
    SCOPE = "https://www.googleapis.com/auth/cloud-platform".freeze
    TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
    @tokens = {}
    @lock = Mutex.new

    def self.json?(secret) = secret.to_s.lstrip.start_with?("{")

    def self.access_token(secret)
      credentials = parse(secret)
      @lock.synchronize do
        cached = @tokens[credentials["client_email"]]
        return cached[:token] if cached && cached[:expires_at] > Time.current + 60

        token, expires_in = fetch_token(credentials)
        @tokens[credentials["client_email"]] = { token:, expires_at: Time.current + expires_in }
        token
      end
    end

    def self.parse(secret)
      credentials = JSON.parse(secret)
      unless credentials["type"] == "service_account" && credentials["private_key"].present? && credentials["client_email"].present?
        raise Synthesizer::Error, "ไฟล์ JSON นี้ไม่ใช่ service account key ของ Google Cloud"
      end

      credentials
    rescue JSON::ParserError
      raise Synthesizer::Error, "อ่านไฟล์ service account JSON ไม่ได้ — คัดลอกเนื้อหาไฟล์ทั้งหมดมาวาง"
    end

    def self.fetch_token(credentials)
      now = Time.current.to_i
      claims = { iss: credentials["client_email"], scope: SCOPE, aud: credentials["token_uri"].presence || TOKEN_URL, iat: now, exp: now + 3600 }
      segments = [{ alg: "RS256", typ: "JWT" }, claims].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }
      key = OpenSSL::PKey::RSA.new(credentials["private_key"])
      signature = Base64.urlsafe_encode64(key.sign(OpenSSL::Digest.new("SHA256"), segments.join(".")), padding: false)
      response = Net::HTTP.post_form(URI(claims[:aud]), grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: "#{segments.join('.')}.#{signature}")
      data = JSON.parse(response.body) rescue {}
      raise Synthesizer::Error, "ขอ access token จาก Google ไม่สำเร็จ: #{data['error_description'] || data['error'] || "HTTP #{response.code}"}" unless data["access_token"]

      [data["access_token"], data["expires_in"].to_i.clamp(60, 3600)]
    rescue OpenSSL::PKey::PKeyError
      raise Synthesizer::Error, "private_key ในไฟล์ service account ไม่ถูกต้อง"
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => error
      raise Synthesizer::Error, "เชื่อมต่อ Google เพื่อขอ access token ไม่ได้: #{error.message.truncate(120)}"
    end
  end
end

module CitizenLine
  class IdTokenVerifier
    class VerificationError < StandardError; end

    def self.call(id_token:, channel_id:)
      raise VerificationError, "ไม่พบข้อมูลยืนยันตัวตน LINE" if id_token.blank? || channel_id.blank?

      uri = URI("https://api.line.me/oauth2/v2.1/verify")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(id_token:, client_id: channel_id)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) { |http| http.request(request) }
      payload = JSON.parse(response.body)
      unless response.is_a?(Net::HTTPSuccess) && payload["sub"].present? && payload["aud"].to_s == channel_id.to_s
        raise VerificationError, payload["error_description"].presence || "ยืนยันบัญชี LINE ไม่สำเร็จ"
      end

      payload
    rescue JSON::ParserError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => error
      raise VerificationError, "ตรวจสอบบัญชี LINE ไม่สำเร็จ: #{error.message}"
    end
  end
end

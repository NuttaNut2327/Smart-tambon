require "resolv"

module Notifications
  # One sender per channel kind. Each raises DeliveryError with a Thai message the admin can act on.
  module Senders
    class DeliveryError < StandardError; end

    def self.for(channel, setting = NotificationSetting.current)
      raise DeliveryError, "ผู้ดูแลระบบปิดช่องทาง #{channel.kind_label} ไว้" unless setting.kind_available?(channel.kind)

      { "line" => Line, "telegram" => Telegram, "signal" => Signal, "webhook" => Webhook }.fetch(channel.kind).new(channel, setting)
    end

    class Base
      TIMEOUT = 15

      def initialize(channel, setting)
        @channel = channel
        @setting = setting
      end

      private

      def post_json(url, body, headers = {})
        uri = URI.parse(url)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        headers.each { |key, value| request[key] = value }
        request.body = body.is_a?(String) ? body : body.to_json
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: TIMEOUT) { |http| http.request(request) }
        [response, (JSON.parse(response.body) if response.body.present? rescue nil)]
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, URI::InvalidURIError => error
        raise DeliveryError, "เชื่อมต่อไม่ได้: #{error.message.truncate(120)}"
      end

      def get_json(url, headers = {})
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        headers.each { |key, value| request[key] = value }
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: TIMEOUT) { |http| http.request(request) }
        [response, (JSON.parse(response.body) if response.body.present? rescue nil)]
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, URI::InvalidURIError => error
        raise DeliveryError, "เชื่อมต่อไม่ได้: #{error.message.truncate(120)}"
      end
    end

    # LINE Messaging API push through the system's Official Account.
    class Line < Base
      API = "https://api.line.me/v2/bot".freeze
      MAX_TEXT = 5000

      def self.client(setting = NotificationSetting.current) = new(nil, setting)

      def deliver(text, **)
        push(@channel.target, text)
      end

      def push(to, text)
        response, data = post_json("#{API}/message/push", { to: to, messages: [{ type: "text", text: text.to_s.truncate(MAX_TEXT) }] }, auth)
        check!(response, data)
      end

      def reply(reply_token, text)
        response, data = post_json("#{API}/message/reply", { replyToken: reply_token, messages: [{ type: "text", text: text.truncate(MAX_TEXT) }] }, auth)
        check!(response, data)
      end

      def bot_info
        response, data = get_json("#{API}/info", auth)
        check!(response, data)
        data
      end

      def group_summary(group_id)
        response, data = get_json("#{API}/group/#{ERB::Util.url_encode(group_id)}/summary", auth)
        response.is_a?(Net::HTTPSuccess) ? data : nil
      end

      private

      def auth
        token = @setting.secret("line_channel_access_token")
        raise DeliveryError, "ผู้ดูแลระบบยังไม่ได้ตั้งค่า Channel access token ของ LINE OA" if token.blank?

        { "Authorization" => "Bearer #{token}" }
      end

      def check!(response, data)
        return true if response.is_a?(Net::HTTPSuccess)

        message = data.is_a?(Hash) ? [data["message"], Array(data["details"]).map { |detail| detail["message"] }.join(", ").presence].compact.join(" — ") : response.body.to_s
        hint = case response.code.to_i
               when 401 then " (token ไม่ถูกต้องหรือหมดอายุ)"
               when 400 then " (ตรวจสอบ Group ID และให้แน่ใจว่าบอทยังอยู่ในกลุ่ม)"
               when 429 then " (เกินโควตาข้อความของ LINE OA เดือนนี้หรือส่งถี่เกินไป)"
               else ""
               end
        raise DeliveryError, "LINE ตอบกลับ #{response.code}: #{message.to_s.truncate(200)}#{hint}"
      end
    end

    # Telegram Bot API; the อบต.'s own bot token wins over the shared one.
    class Telegram < Base
      MAX_TEXT = 4096

      def deliver(text, **)
        response, data = post_json("#{api}/sendMessage", { chat_id: @channel.target, text: text.to_s.truncate(MAX_TEXT), disable_web_page_preview: true })
        return true if response.is_a?(Net::HTTPSuccess) && data&.dig("ok")

        raise DeliveryError, "Telegram ตอบกลับ #{response.code}: #{data&.dig('description') || response.body.to_s.truncate(200)}"
      end

      # Chats that recently messaged the bot, to help find a group's Chat ID.
      def recent_chats
        response, data = get_json("#{api}/getUpdates?allowed_updates=%5B%22message%22,%22my_chat_member%22%5D")
        raise DeliveryError, "Telegram ตอบกลับ #{response.code}: #{data&.dig('description')}" unless response.is_a?(Net::HTTPSuccess) && data&.dig("ok")

        Array(data["result"]).filter_map { |update| (update["message"] || update["my_chat_member"])&.dig("chat") }
                             .uniq { |chat| chat["id"] }
                             .map { |chat| { id: chat["id"].to_s, title: chat["title"] || [chat["first_name"], chat["last_name"]].compact.join(" "), type: chat["type"] } }
      end

      private

      def api
        token = @channel&.token.presence || @setting.secret("telegram_bot_token")
        raise DeliveryError, "ยังไม่มี Bot token ของ Telegram — ใส่ในช่องทางนี้ หรือให้ผู้ดูแลระบบตั้งบอทกลาง" if token.blank?

        "https://api.telegram.org/bot#{token}"
      end
    end

    # Signal through a signal-cli-rest-api gateway registered with the system's number.
    class Signal < Base
      def deliver(text, **)
        raise DeliveryError, "ผู้ดูแลระบบยังไม่ได้ตั้งค่า Signal gateway และเบอร์ผู้ส่ง" unless @setting.signal_ready?

        response, data = post_json("#{@setting.signal_api_url}/v2/send", { message: text, number: @setting.signal_number, recipients: [@channel.target] })
        return true if response.is_a?(Net::HTTPSuccess)

        raise DeliveryError, "Signal gateway ตอบกลับ #{response.code}: #{(data.is_a?(Hash) ? data['error'] : response.body).to_s.truncate(200)}"
      end

      def groups
        raise DeliveryError, "ผู้ดูแลระบบยังไม่ได้ตั้งค่า Signal gateway และเบอร์ผู้ส่ง" unless @setting.signal_ready?

        response, data = get_json("#{@setting.signal_api_url}/v1/groups/#{ERB::Util.url_encode(@setting.signal_number)}")
        raise DeliveryError, "Signal gateway ตอบกลับ #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        Array(data).map { |group| { id: group["id"], title: group["name"], type: "group" } }
      end
    end

    # Generic outgoing webhook for other systems. Signed with HMAC-SHA256 when a secret is set.
    class Webhook < Base
      def deliver(text, tag: nil, data: {})
        guard_private_address!(@channel.target)
        body = { event: tag, text: text, data: data, organization: @channel.organization_key, sent_at: Time.current.iso8601 }.to_json
        headers = { "User-Agent" => "SmartTambon-Notifier/1.0" }
        headers["X-SmartTambon-Signature"] = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @channel.token, body)}" if @channel.token.present?
        response, = post_json(@channel.target, body, headers)
        return true if response.is_a?(Net::HTTPSuccess)

        raise DeliveryError, "Webhook ตอบกลับ #{response.code}"
      end

      private

      # อบต. admins choose this URL, so it must not reach the app's own network (databases, metadata services).
      def guard_private_address!(url)
        return if ENV["NOTIFICATION_ALLOW_PRIVATE_WEBHOOKS"] == "1"

        host = URI.parse(url).host
        addresses = Resolv.getaddresses(host)
        raise DeliveryError, "หาที่อยู่ของ #{host} ไม่พบ" if addresses.empty?

        blocked = addresses.map { |address| IPAddr.new(address) }.find { |ip| ip.private? || ip.loopback? || ip.link_local? || ip.to_s == "0.0.0.0" }
        raise DeliveryError, "ไม่อนุญาตให้ส่ง Webhook ไปยังที่อยู่ภายในเครือข่าย (#{blocked})" if blocked
      rescue URI::InvalidURIError, IPAddr::InvalidAddressError
        raise DeliveryError, "Webhook URL ไม่ถูกต้อง"
      end
    end
  end
end

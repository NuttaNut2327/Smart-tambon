module CitizenLine
  class Client < Notifications::Senders::Base
    API = "https://api.line.me/v2/bot".freeze

    def initialize(setting:)
      super(nil, setting)
    end

    def push(user_id, text)
      response, data = post_json("#{API}/message/push", { to: user_id, messages: [{ type: "text", text: text.to_s.truncate(5000) }] }, auth)
      check!(response, data)
    end

    def reply(reply_token, text)
      response, data = post_json("#{API}/message/reply", { replyToken: reply_token, messages: [{ type: "text", text: text.to_s.truncate(5000) }] }, auth)
      check!(response, data)
    end

    def bot_info
      response, data = get_json("#{API}/info", auth)
      check!(response, data)
      data
    end

    private

    def auth
      token = @setting.citizen_line_channel_access_token
      raise Notifications::Senders::DeliveryError, "ยังไม่ได้ตั้งค่า Channel access token ของ LINE OA ประชาชน" if token.blank?

      { "Authorization" => "Bearer #{token}" }
    end

    def check!(response, data)
      return true if response.is_a?(Net::HTTPSuccess)

      message = data.is_a?(Hash) ? data["message"] : response.body.to_s
      raise Notifications::Senders::DeliveryError, "LINE OA ประชาชนตอบกลับ #{response.code}: #{message.to_s.truncate(200)}"
    end
  end
end

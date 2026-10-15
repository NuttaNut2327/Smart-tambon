module Webhooks
  # LINE Messaging API webhook (set it in the LINE Developers console as https://<host>/webhooks/line).
  # Verifies X-Line-Signature with the channel secret, records groups the bot joins or leaves, and replies with the
  # group ID when invited or when someone types "groupid" so อบต. staff can paste it into their channel settings.
  class LineController < ActionController::API
    GROUP_ID_COMMANDS = %w[groupid group_id /groupid ไอดีกลุ่ม].freeze

    def create
      setting = NotificationSetting.current
      secret = setting.secret("line_channel_secret")
      body = request.raw_post
      return head :service_unavailable if secret.blank?
      return head :unauthorized unless valid_signature?(body, secret)

      Array(JSON.parse(body)["events"]).each { |event| handle(event, setting) }
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def valid_signature?(body, secret)
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, body))
      ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Line-Signature"].to_s)
    end

    def handle(event, setting)
      source = event["source"].to_h
      group_id = source["groupId"] || source["roomId"]
      return unless group_id

      line = Notifications::Senders::Line.client(setting)
      group = LineGroup.find_or_initialize_by(group_id: group_id)
      group.source_type = source["groupId"] ? "group" : "room"
      group.last_event_at = Time.current
      case event["type"]
      when "join"
        group.joined_at = Time.current
        group.left_at = nil
        if (summary = line.group_summary(group_id))
          group.group_name = summary["groupName"]
          group.picture_url = summary["pictureUrl"]
        end
        reply(line, event, group_id) if setting.line_reply_group_id?
      when "leave"
        group.left_at = Time.current
      when "message"
        text = event.dig("message", "text").to_s.strip.downcase
        reply(line, event, group_id) if GROUP_ID_COMMANDS.include?(text)
      end
      group.save!
    rescue Notifications::Senders::DeliveryError => error
      Rails.logger.warn("LINE webhook reply failed: #{error.message}")
      group&.save
    end

    def reply(line, event, group_id)
      return if event["replyToken"].blank?

      line.reply(event["replyToken"], "สวัสดีครับ บอทแจ้งเตือนของ #{SystemSetting.current.system_short_name} พร้อมใช้งาน\n\n" \
                                      "Group ID ของกลุ่มนี้คือ:\n#{group_id}\n\n" \
                                      "คัดลอกไปใส่ที่ ตั้งค่า อบต. → ช่องทางแจ้งเตือน → เพิ่มช่องทาง LINE OA")
    end
  end
end

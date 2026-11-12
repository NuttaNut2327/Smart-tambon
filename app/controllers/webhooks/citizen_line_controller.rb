module Webhooks
  class CitizenLineController < ActionController::API
    def create
      setting = OrganizationSetting.find_by(organization_key: params[:organization_key])
      return head :not_found unless setting
      secret = setting.citizen_line_channel_secret
      body = request.raw_post
      return log_and_head(body, "configuration_error", :service_unavailable) if secret.blank?
      return log_and_head(body, "invalid_signature", :unauthorized) unless valid_signature?(body, secret)

      payload = JSON.parse(body)
      Array(payload["events"]).each { |event| handle(event, setting) }
      record_log(body, payload, "accepted", true)
      head :ok
    rescue JSON::ParserError
      log_and_head(request.raw_post, "invalid_json", :bad_request, true)
    end

    private

    def valid_signature?(body, secret)
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, body))
      ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Line-Signature"].to_s)
    end

    def handle(event, setting)
      return unless event["type"] == "message" && event.dig("message", "type") == "text" && event["replyToken"].present?

      CitizenLine::Client.new(setting:).reply(event["replyToken"], "สวัสดีครับ สามารถกดเมนูแจ้งเหตุเพื่อส่งข้อมูลให้เจ้าหน้าที่ได้")
    rescue Notifications::Senders::DeliveryError => error
      Rails.logger.warn("Citizen LINE webhook reply failed: #{error.message}")
    end

    def log_and_head(body, status, http_status, signature_valid = false)
      record_log(body, nil, status, signature_valid)
      head http_status
    end

    def record_log(body, payload, status, signature_valid)
      parsed = payload || (JSON.parse(body) if signature_valid)
      events = Array(parsed&.fetch("events", nil))
      LineWebhookLog.create!(account_key: "citizen", organization_key: params[:organization_key], received_at: Time.current, status:, signature_valid:,
        event_types: events.filter_map { |event| event["type"].presence }.uniq,
        destination: parsed&.fetch("destination", nil), payload: parsed || {}, body_size: body.to_s.bytesize,
        request_id: request.request_id)
    rescue JSON::ParserError, Mongo::Error, Mongoid::Errors::MongoidError => error
      Rails.logger.warn("Citizen LINE webhook log could not be saved: #{error.message}")
    end
  end
end

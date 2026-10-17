module Broadcasts
  # Sends a broadcast to its channels: text (+ image) to Facebook/Instagram/LINE/Telegram/Signal/webhooks and the
  # voice file to the PA system over MQTT. Each channel succeeds or fails on its own; results go to the delivery log.
  class Publisher
    def self.call(broadcast) = new(broadcast).call

    def initialize(broadcast)
      @broadcast = broadcast
    end

    def call
      channels = @broadcast.channels.select(&:enabled?)
      raise "ยังไม่ได้เลือกช่องทางเผยแพร่" if channels.empty?
      raise "เสียงยังไม่ตรงกับข้อความล่าสุด — สร้างเสียงใหม่ก่อนส่งไปเสียงตามสาย" if channels.any? { |channel| channel.kind == "pa_mqtt" } && !@broadcast.audio_current?

      @broadcast.set(status: "publishing", error_message: nil)
      results = channels.map { |channel| deliver(channel) }
      failures = results.count(false)
      @broadcast.set(status: "published", published_at: Time.current,
                     error_message: failures.positive? ? "ส่งไม่สำเร็จ #{failures} จาก #{results.size} ช่องทาง — ดูรายละเอียดในประวัติการส่ง" : nil)
    end

    private

    def deliver(channel)
      reference = Notifications::Senders.for(channel).deliver(@broadcast.post_text, tag: "broadcast", data: payload_for(channel))
      channel.set(last_sent_at: Time.current, last_error: nil)
      @broadcast.log_delivery!(channel, status: "sent", reference: reference.to_s.presence)
      true
    rescue Notifications::Senders::DeliveryError, StandardError => error
      channel.set(last_error: error.message.to_s.truncate(300))
      @broadcast.log_delivery!(channel, status: "failed", error: error.message.to_s.truncate(300))
      false
    end

    def payload_for(channel)
      data = { broadcast_id: @broadcast.id.to_s, title: @broadcast.title, bullets: @broadcast.bullets, image_url: Media.public_url(@broadcast, :image) }
      if channel.kind == "pa_mqtt" || channel.kind == "webhook"
        audio = @broadcast.audio
        data.merge!(audio_url: Media.public_url(@broadcast, :audio), audio_content_type: audio&.dig("content_type"),
                    audio_bytes: audio&.dig("byte_size"), audio_sha256: audio&.dig("sha256"), script: @broadcast.script,
                    expires_at: (Time.current + Media::LINK_TTL).iso8601)
      end
      data.compact
    end
  end
end

module Broadcasts
  # Sends a broadcast through its delivery modes: text (+ image) to Facebook/Instagram/LINE/Telegram/Signal/webhooks,
  # the voice file to the PA system over MQTT and an in-app alert for the อบต.'s signed-in staff. Each target succeeds
  # or fails on its own; results go to the delivery log.
  class Publisher
    InternalTarget = Struct.new(:id, :name, :kind)

    def self.call(broadcast) = new(broadcast).call

    def initialize(broadcast)
      @broadcast = broadcast
    end

    def call
      channels = @broadcast.channels.select(&:enabled?)
      internal = @broadcast.delivers?("internal")
      raise "ยังไม่ได้เลือกรูปแบบหรือช่องทางเผยแพร่" if channels.empty? && !internal
      raise "เสียงยังไม่ตรงกับข้อความล่าสุด — สร้างเสียงใหม่ก่อนส่งไปเสียงตามสาย" if channels.any? { |channel| channel.kind == "pa_mqtt" } && !@broadcast.audio_current?

      @broadcast.set(status: "publishing", error_message: nil)
      results = channels.map { |channel| deliver(channel) }
      results << deliver_internal if internal
      failures = results.count(false)
      @broadcast.set(status: "published", published_at: Time.current,
                     error_message: failures.positive? ? "ส่งไม่สำเร็จ #{failures} จาก #{results.size} ช่องทาง — ดูรายละเอียดในประวัติการส่ง" : nil)
    end

    private

    def deliver(channel)
      reference = Notifications::Service.publish(
        channel: channel,
        text: @broadcast.post_text,
        event: "broadcast",
        data: payload_for(channel)
      )
      channel.set(last_sent_at: Time.current, last_error: nil)
      @broadcast.log_delivery!(channel, status: "sent", reference: reference.to_s.presence)
      true
    rescue Notifications::Senders::DeliveryError, StandardError => error
      channel.set(last_error: error.message.to_s.truncate(300))
      @broadcast.log_delivery!(channel, status: "failed", error: error.message.to_s.truncate(300))
      false
    end

    # One Announcement per broadcast; publishing again refreshes it and shows it to everyone again.
    def deliver_internal
      target = InternalTarget.new("internal", BroadcastDelivery::MODES.dig("internal", :label), BroadcastDelivery::INTERNAL_KIND)
      announcement = Announcement.find_or_initialize_by(broadcast_id: @broadcast.id)
      now = Time.current
      announcement.assign_attributes(title: @broadcast.title.presence || @broadcast.program_name, body: @broadcast.post_text.presence || @broadcast.program_name,
                                     level: @broadcast.internal_alert_level, frequency: "once", display_mode: "dismissible", active: true,
                                     starts_at: now, ends_at: now + @broadcast.internal_alert_hours.hours,
                                     target_organization_key: @broadcast.organization_key, target_roles: [], target_subdistrict_ids: [])
      announcement.receipts.delete_all if announcement.persisted?
      announcement.save!
      @broadcast.log_delivery!(target, status: "sent", reference: announcement.id.to_s)
      true
    rescue StandardError => error
      @broadcast.log_delivery!(target, status: "failed", error: error.message.to_s.truncate(300))
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

module Notifications
  # Renders a tag's template for an อบต. and sends it to every enabled channel subscribed to that tag,
  # logging one NotificationDelivery per channel. Failures on one channel never stop the others.
  class Dispatcher
    THAI_MONTHS = %w[ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย. ต.ค. พ.ย. ธ.ค.].freeze
    SEVERITIES = { "critical" => "วิกฤต", "very_urgent" => "เร่งด่วนมาก", "urgent" => "เร่งด่วน", "watch" => "เฝ้าระวัง",
                   "non_urgent" => "ไม่เร่งด่วน", "waiting" => "รอประเมิน", "general" => "ทั่วไป" }.freeze
    STATUSES = { "pending" => "รอรับเรื่อง", "assessing" => "กำลังประเมิน", "in_progress" => "กำลังดำเนินการ", "completed" => "เสร็จสิ้น" }.freeze

    def self.render(body, variables)
      body.to_s.gsub(/\{\{\s*([a-z_]+)\s*\}\}/) { variables[Regexp.last_match(1)].to_s }.gsub(/\n{3,}/, "\n\n").strip
    end

    def self.tag_for(incident) = "#{incident.category == 'general' ? 'incident' : incident.category}.created"

    # Organisations that should hear about an incident: the owner's, or those of users assigned to its subdistrict.
    def self.organization_keys_for(incident)
      if incident.owner_user_id
        Array(User.where(id: incident.owner_user_id).pick(:organization_key))
      elsif incident.subdistrict_id
        User.where(subdistrict_id: incident.subdistrict_id).where.not(role: :system_admin).distinct.pluck(:organization_key)
      else
        []
      end.compact
    end

    def self.incident_variables(incident, organization_key)
      setting = NotificationSetting.current
      base = setting.base_url
      type = incident.category == "activity" ? Incident::ACTIVITY_TYPES.dig(incident.incident_type, :label) : incident.incident_type_other.presence || incident.incident_type
      page = { "disaster" => "disasters", "activity" => "activities" }.fetch(incident.category, "general_incidents")
      located = incident.latitude.present? && incident.longitude.present?
      {
        "reference_code" => incident.reference_code, "category" => { "disaster" => "ภัยพิบัติ", "activity" => "กิจกรรม" }.fetch(incident.category, "เหตุการณ์ทั่วไป"),
        "incident_type" => type, "title" => incident.title, "description" => incident.description.to_s.truncate(500),
        "severity" => SEVERITIES.fetch(incident.severity.to_s, incident.severity), "status" => STATUSES.fetch(incident.status.to_s, incident.status),
        "report_source" => incident.report_source_name, "location_name" => incident.location_name,
        "subdistrict" => incident.subdistrict_id && Subdistrict.where(id: incident.subdistrict_id).pick(:name_th),
        "latitude" => incident.latitude&.round(6), "longitude" => incident.longitude&.round(6),
        "map_url" => (located ? "https://maps.google.com/?q=#{incident.latitude},#{incident.longitude}" : nil),
        "affected_people" => incident.affected_people.to_i, "affected_households" => incident.affected_households.to_i,
        "activity_starts_at" => thai_time(incident.starts_at), "activity_ends_at" => thai_time(incident.ends_at),
        "reported_at" => thai_time(incident.occurred_at || incident.created_at),
        "link" => (base ? "#{base}/#{page}?incident_id=#{incident.id}" : nil)
      }.merge(context_variables(organization_key))
    end

    def self.context_variables(organization_key)
      { "system_name" => SystemSetting.current.system_name,
        "organization_name" => OrganizationSetting.where(organization_key: organization_key).pick(:organization_name) || "อบต." }
    end

    # Placeholder data for previews and tests before any real incident exists.
    def self.sample_variables(organization_key)
      {
        "reference_code" => "INC-#{Time.current.year + 543}-TEST01", "category" => "เหตุการณ์ทั่วไป", "incident_type" => "ไฟฟ้าดับ",
        "title" => "[ทดสอบ] ไฟฟ้าดับบริเวณหมู่ 3", "description" => "ข้อความทดสอบจากระบบ", "severity" => "เร่งด่วน", "status" => "รอรับเรื่อง",
        "report_source" => "ประชาชน", "location_name" => "ศาลาประชาคมหมู่ 3", "subdistrict" => "ตัวอย่าง",
        "latitude" => 13.7563, "longitude" => 100.5018, "map_url" => "https://maps.google.com/?q=13.7563,100.5018",
        "affected_people" => 12, "affected_households" => 4, "activity_starts_at" => thai_time(1.day.from_now),
        "activity_ends_at" => thai_time(1.day.from_now + 3.hours), "reported_at" => thai_time(Time.current),
        "link" => NotificationSetting.current.base_url&.then { |base| "#{base}/general_incidents" }, "message" => "ข้อความประกาศทดสอบ"
      }.merge(context_variables(organization_key))
    end

    def self.thai_time(time)
      return nil unless time

      time = time.in_time_zone
      "#{time.day} #{THAI_MONTHS[time.month - 1]} #{time.year + 543} #{time.strftime('%H:%M')} น."
    end

    def initialize(organization_key:, sent_by: nil, source: "event")
      @organization_key = organization_key
      @sent_by = sent_by
      @source = source
    end

    def dispatch(tag:, variables:, incident_id: nil, channels: nil, body: nil)
      channels ||= NotificationChannel.for_organization(@organization_key).enabled.select { |channel| channel.subscribed?(tag) }
      text = self.class.render(body || NotificationTemplate.body_for(@organization_key, tag), variables)
      setting = NotificationSetting.current
      channels.map { |channel| deliver(channel, text, tag: tag, variables: variables, incident_id: incident_id, setting: setting) }
    end

    def deliver(channel, text, tag:, variables: {}, incident_id: nil, setting: NotificationSetting.current)
      Senders.for(channel, setting).deliver(text, tag: tag, data: variables)
      channel.set(last_sent_at: Time.current, last_error: nil)
      log(channel, text, tag, incident_id, "sent")
    rescue Senders::DeliveryError => error
      channel.set(last_error: error.message)
      log(channel, text, tag, incident_id, "failed", error.message)
    rescue StandardError => error
      Rails.logger.error("Notification to #{channel.kind} #{channel.id} failed: #{error.class}: #{error.message}")
      channel.set(last_error: "เกิดข้อผิดพลาดภายใน")
      log(channel, text, tag, incident_id, "failed", "เกิดข้อผิดพลาดภายใน (#{error.class})")
    end

    private

    def log(channel, text, tag, incident_id, status, error = nil)
      NotificationDelivery.create!(organization_key: @organization_key, channel_id: channel.id, channel_name: channel.name, kind: channel.kind,
                                   tag: tag, source: @source, incident_id: incident_id, status: status, error: error, text: text, sent_by: @sent_by)
    end
  end
end

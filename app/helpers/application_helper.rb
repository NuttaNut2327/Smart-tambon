module ApplicationHelper
  THAI_SHORT_MONTHS = %w[ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย. ต.ค. พ.ย. ธ.ค.].freeze

  def system_setting = @system_setting ||= SystemSetting.current
  def organization_setting = defined?(@organization_setting) ? @organization_setting : (@organization_setting = OrganizationSetting.for(current_user))
  def system_name = system_setting.system_name
  def system_short_name = system_setting.system_short_name

  def system_logo_src
    system_setting.logo.present? ? logo_system_settings_path(v: system_setting.logo["id"]) : image_path("logo-smart-tambon.png")
  end

  # Map basemap, layers and initial view for the signed-in user: the อบต. settings override the system defaults.
  def map_defaults
    organization_setting ? organization_setting.map_defaults(system_setting) : system_setting.map_defaults
  end

  def map_layer_default?(key) = map_defaults[:layers].include?(key.to_s)

  def thai_short_datetime(value)
    return "—" if value.blank?

    time = value.in_time_zone("Asia/Bangkok")
    "#{time.day} #{THAI_SHORT_MONTHS[time.month - 1]} #{time.year + 543} #{time.strftime('%H:%M')} น."
  end

  # "14 ต.ค. 2569 09:00–17:00 น." on one day, otherwise both full date-times.
  def thai_period(starts_at, ends_at)
    return thai_short_datetime(starts_at || ends_at) if starts_at.blank? || ends_at.blank?
    return "#{thai_short_date(starts_at)} #{starts_at.in_time_zone('Asia/Bangkok').strftime('%H:%M')}–#{thai_short_time(ends_at)}" if starts_at.in_time_zone("Asia/Bangkok").to_date == ends_at.in_time_zone("Asia/Bangkok").to_date

    "#{thai_short_datetime(starts_at)} – #{thai_short_datetime(ends_at)}"
  end

  def thai_short_date(value)
    return "—" if value.blank?

    date = if value.is_a?(Date) && !value.is_a?(DateTime)
      value
    else
      value.in_time_zone("Asia/Bangkok").to_date
    end
    "#{date.day} #{THAI_SHORT_MONTHS[date.month - 1]} #{date.year + 543}"
  end

  def thai_short_time(value)
    return "—" if value.blank?

    value.in_time_zone("Asia/Bangkok").strftime("%H:%M น.")
  end

  def thai_numeric_datetime(value)
    return "—" if value.blank?

    value.in_time_zone("Asia/Bangkok").strftime("%d/%m/%Y %H:%M")
  end

  def thai_incident_datetime(value)
    return "—" if value.blank?
    return thai_short_datetime(value) unless value.is_a?(String)

    time = if value.match?(%r{\A\d{2}/\d{2}/\d{4} \d{2}:\d{2}\z})
      # Incident history used to be stored as a UTC string without an offset.
      Time.find_zone!("UTC").strptime(value, "%d/%m/%Y %H:%M")
    else
      Time.zone.parse(value)
    end
    time ? thai_short_datetime(time) : value
  rescue ArgumentError, TypeError
    value
  end

  def pending_incident_count
    return 0 unless current_user

    @pending_incident_count ||= Incident.visible_to(current_user).where(category: "general", status: "pending").count
  rescue Mongoid::Errors::MongoidError
    0
  end

  # Activities still waiting for someone to acknowledge them ("รับเรื่อง").
  def pending_activity_count
    return 0 unless current_user

    return 0 if organization_setting&.notify_pending_activities == false

    @pending_activity_count ||= Incident.visible_to(current_user).activities.where(status: "pending", :ends_at.gt => Time.current).count
  rescue Mongoid::Errors::MongoidError
    0
  end

  def pending_disaster_count
    return 0 unless current_user

    @pending_disaster_count ||= Incident.visible_to(current_user).where(category: "disaster", status: "pending").count
  rescue Mongoid::Errors::MongoidError
    0
  end

  # Reporting sources each get their own permanent public form link; edited in the อบต. settings.
  def public_report_sources
    sources = organization_setting&.report_sources || OrganizationSetting::DEFAULT_REPORT_SOURCES
    sources.map { |source| { type: source["type"], name: source["name"], label: source["name"] } }
  end

  def public_incident_report_link(source_type: "citizen", source_name: "ประชาชน")
    scope = if current_user.access_area.present?
      { scope: "access_area", id: current_user.access_area.id, version: 1 }
    else
      { scope: "account", id: current_user.id, version: 1 }
    end
    # Bumped by "สร้างลิงก์ใหม่" in the อบต. settings, which invalidates previously shared links.
    scope[:version] = organization_setting&.public_report_version || 1
    scope[:source_type] = source_type
    scope[:source_name] = source_name
    token = Rails.application.message_verifier(:public_incident_form).generate(scope)
    public_incident_report_url(token: token)
  end

  def operational_status_badge(status)
    value = status.presence || "—"
    tone = case value
           when "พร้อมปฏิบัติงาน", "พร้อมใช้งาน", "พร้อมใช้", "เชื่อมแล้ว" then "ready"
           when "กำลังปฏิบัติงาน", "กำลังใช้งาน", "รอตรวจสอบ" then "active"
           when "ไม่พร้อมปฏิบัติงาน", "ติดภารกิจ" then "unavailable"
           when "ยังไม่เชื่อมขอบเขต", "ยังไม่เชื่อม" then "neutral"
           else "neutral"
           end
    content_tag(:span, value, class: "operational-status-badge #{tone}")
  end
end

module ApplicationHelper
  THAI_SHORT_MONTHS = %w[ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย. ต.ค. พ.ย. ธ.ค.].freeze

  def thai_short_datetime(value)
    return "—" if value.blank?

    time = value.in_time_zone("Asia/Bangkok")
    "#{time.day} #{THAI_SHORT_MONTHS[time.month - 1]} #{time.year + 543} #{time.strftime('%H:%M')} น."
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

  def pending_disaster_count
    return 0 unless current_user

    @pending_disaster_count ||= Incident.visible_to(current_user).where(category: "disaster", status: "pending").count
  rescue Mongoid::Errors::MongoidError
    0
  end

  def public_report_sources
    [
      { type: "citizen", name: "ประชาชน", label: "ประชาชน" },
      { type: "organization", name: "หน่วยงาน 1", label: "หน่วยงาน 1" },
      { type: "organization", name: "หน่วยงาน 2", label: "หน่วยงาน 2" },
      { type: "organization", name: "โรงพยาบาลส่งเสริมสุขภาพตำบล", label: "โรงพยาบาลส่งเสริมสุขภาพตำบล" },
      { type: "organization", name: "สถานีตำรวจภูธร", label: "สถานีตำรวจภูธร" }
    ]
  end

  def public_incident_report_link(source_type: "citizen", source_name: "ประชาชน")
    scope = if current_user.access_area.present?
      { scope: "access_area", id: current_user.access_area.id, version: 1 }
    else
      { scope: "account", id: current_user.id, version: 1 }
    end
    scope[:source_type] = source_type
    scope[:source_name] = source_name
    token = Rails.application.message_verifier(:public_incident_form).generate(scope)
    public_incident_report_url(token: token)
  end
end

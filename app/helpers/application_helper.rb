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
    return value.in_time_zone("Asia/Bangkok").strftime("%d/%m/%Y %H:%M") unless value.is_a?(String)

    time = if value.match?(%r{\A\d{2}/\d{2}/\d{4} \d{2}:\d{2}\z})
      # Incident history used to be stored as a UTC string without an offset.
      Time.find_zone!("UTC").strptime(value, "%d/%m/%Y %H:%M")
    else
      Time.zone.parse(value)
    end
    time&.in_time_zone("Asia/Bangkok")&.strftime("%d/%m/%Y %H:%M") || value
  rescue ArgumentError, TypeError
    value
  end

  def pending_incident_count
    return 0 unless current_user

    @pending_incident_count ||= Incident.visible_to(current_user).where(status: "pending").count
  rescue Mongoid::Errors::MongoidError
    0
  end
end

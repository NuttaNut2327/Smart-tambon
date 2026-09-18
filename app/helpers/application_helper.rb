module ApplicationHelper
  THAI_SHORT_MONTHS = %w[ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย. ต.ค. พ.ย. ธ.ค.].freeze

  def thai_short_datetime(value)
    return "—" if value.blank?

    time = value.in_time_zone
    "#{time.day} #{THAI_SHORT_MONTHS[time.month - 1]} #{time.year + 543} #{time.strftime('%H:%M')} น."
  end

  def pending_incident_count
    return 0 unless current_user

    @pending_incident_count ||= Incident.visible_to(current_user).where(status: "pending").count
  rescue Mongoid::Errors::MongoidError
    0
  end
end

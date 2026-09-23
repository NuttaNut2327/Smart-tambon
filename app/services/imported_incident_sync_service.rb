class ImportedIncidentSyncService
  SEVERITY_VALUES = {
    "รอได้" => "waiting", "waiting" => "waiting",
    "เฝ้าระวัง" => "watch", "watch" => "watch",
    "เร่งด่วน" => "urgent", "urgent" => "urgent",
    "วิกฤต" => "critical", "critical" => "critical"
  }.freeze
  STATUS_VALUES = {
    "รอรับเรื่อง" => "pending", "pending" => "pending",
    "กำลังประเมิน" => "assessing", "assessing" => "assessing",
    "กำลังดำเนินการ" => "in_progress", "in_progress" => "in_progress",
    "เสร็จสิ้น" => "completed", "completed" => "completed"
  }.freeze

  def self.parse_occurred_at(value)
    text = value.to_s.strip
    raise ArgumentError, "วันและเวลาเกิดเหตุไม่ถูกต้อง" if text.blank?

    zone = Time.find_zone!("Asia/Bangkok")
    time = if text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\z})
      zone.strptime(text, "%d/%m/%Y %H:%M")
    else
      zone.parse(text)
    end
    raise ArgumentError, "วันและเวลาเกิดเหตุไม่ถูกต้อง" unless time

    time
  rescue ArgumentError => error
    raise error if error.message == "วันและเวลาเกิดเหตุไม่ถูกต้อง"
    raise ArgumentError, "วันและเวลาเกิดเหตุไม่ถูกต้อง"
  end

  def self.normalize_severity(value)
    SEVERITY_VALUES[value.to_s.strip] || raise(ArgumentError, "ระดับความรุนแรงไม่ถูกต้อง")
  end

  def self.normalize_status(value)
    STATUS_VALUES[value.to_s.strip] || raise(ArgumentError, "สถานะเหตุการณ์ไม่ถูกต้อง")
  end

  def initialize(dataset:, user:, records:)
    @dataset = dataset
    @user = user
    @records = records
  end

  def sync!
    reference_codes = @records.map { |record| record.fetch("reference_code") }
    @records.each { |record| sync_record(record) }
    Incident.where(imported_dataset_id: @dataset.id.to_s, :reference_code.nin => reference_codes).destroy_all
  end

  private

  def sync_record(record)
    incident = Incident.find_or_initialize_by(reference_code: record.fetch("reference_code"))
    is_new = incident.new_record?
    incident.assign_attributes(
      imported_dataset_id: @dataset.id.to_s,
      user_id: incident.user_id || @user.id,
      subdistrict_id: @dataset.subdistrict_id,
      category: "general",
      incident_type: record["incident_type"],
      title: record["title"],
      description: record["description"],
      severity: self.class.normalize_severity(record["severity"]),
      status: self.class.normalize_status(record["status"]),
      reporter_name: record["reporter_name"],
      reporter_contact: record["reporter_contact"],
      location_name: record["location_name"].presence || "ตำแหน่งจากชุดข้อมูลแจ้งเหตุการณ์",
      longitude: record["longitude"],
      latitude: record["latitude"],
      initial_impact: record["initial_impact"],
      backdated: true,
      occurred_at: self.class.parse_occurred_at(record["occurred_at"])
    )
    if is_new
      incident.histories << {
        "title" => "นำเข้าข้อมูลแจ้งเหตุการณ์",
        "description" => "สร้างเหตุการณ์ทั่วไปจากชุดข้อมูล #{@dataset.name}",
        "occurred_at" => Time.current.utc.iso8601,
        "actor" => @user.username,
        "resources" => []
      }
    end
    incident.save!
  end
end

class Incident
  include Mongoid::Document
  include Mongoid::Timestamps

  CATEGORIES = %w[disaster general activity].freeze
  # Planned events in the area (fairs, ceremonies, markets). Stored as incidents with category "activity";
  # incident_type holds the key below and the label/icon drive the list and map marker.
  ACTIVITY_TYPES = {
    "festival" => { label: "งานประจำปี/เทศกาล", icon: "celebration" },
    "religion" => { label: "ศาสนา/ประเพณี", icon: "temple_buddhist" },
    "sport" => { label: "กีฬา/นันทนาการ", icon: "sports_soccer" },
    "market" => { label: "ตลาดนัด/ออกร้าน", icon: "storefront" },
    "meeting" => { label: "ประชุม/อบรม", icon: "groups" },
    "public_service" => { label: "หน่วยบริการเคลื่อนที่", icon: "volunteer_activism" },
    "other" => { label: "กิจกรรมอื่น ๆ", icon: "event" }
  }.freeze
  ACTIVITY_PHASES = { "upcoming" => "กำลังจะเริ่ม", "ongoing" => "กำลังจัดงาน", "finished" => "สิ้นสุดแล้ว" }.freeze
  DISASTER_INCIDENT_TYPES = ["น้ำท่วม", "ไฟป่า", "พายุ", "ดินถล่ม", "ภัยแล้ง", "อื่น ๆ"].freeze
  STATUSES = %w[pending assessing in_progress completed].freeze
  SEVERITIES = %w[general non_urgent urgent very_urgent critical waiting watch].freeze

  field :user_id, type: Integer
  field :owner_user_id, type: Integer
  field :access_area_id, type: Integer
  field :subdistrict_id, type: Integer
  field :report_source_type, type: String, default: "staff"
  field :report_source_name, type: String, default: "เจ้าหน้าที่"
  field :reference_code, type: String
  field :category, type: String, default: "general"
  field :incident_type, type: String
  field :incident_type_other, type: String
  field :title, type: String
  field :description, type: String
  field :backdated, type: Boolean, default: false
  field :occurred_at, type: Time
  field :severity, type: String, default: "general"
  field :status, type: String, default: "pending"
  field :reporter_name, type: String
  field :reporter_contact, type: String
  field :location_name, type: String
  field :longitude, type: Float
  field :latitude, type: Float
  field :affected_people, type: Integer, default: 0
  field :affected_households, type: Integer, default: 0
  field :initial_impact, type: String
  field :photos, type: Array, default: []
  field :assigned_to, type: String
  field :received_by, type: String
  field :received_by_user_id, type: Integer
  field :received_at, type: Time
  field :histories, type: Array, default: []
  field :resources_used, type: Array, default: []
  field :active_assignments, type: Array, default: []
  field :assigned_team_code, type: String
  field :response_plan_versions, type: Array, default: []
  field :active_plan_version, type: Integer
  field :deleted_at, type: Time
  field :deleted_by, type: String
  # Activity-only fields
  field :starts_at, type: Time
  field :ends_at, type: Time
  field :organizer, type: String
  field :expected_attendees, type: Integer
  field :cover_photo_id, type: String

  index({ subdistrict_id: 1, created_at: -1 })
  index({ owner_user_id: 1, report_source_name: 1, created_at: -1 })
  index({ category: 1, status: 1 })
  index({ reference_code: 1 }, { unique: true, sparse: true })
  index({ imported_dataset_id: 1 })
  index({ category: 1, status: 1, ends_at: 1 })

  validates :title, :category, :status, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :occurred_at, presence: true, if: :backdated?
  validates :incident_type_other, presence: true, if: -> { incident_type == "อื่น ๆ" }
  with_options if: :activity? do
    validates :starts_at, :ends_at, :latitude, :longitude, presence: true
    validates :incident_type, inclusion: { in: ACTIVITY_TYPES.keys, message: "กรุณาเลือกประเภทกิจกรรม" }
    validates :expected_attendees, numericality: { only_integer: true, greater_than_or_equal_to: 0, message: "ต้องเป็นจำนวนเต็มไม่ติดลบ" }, allow_nil: true
    validate :activity_must_end_after_start
  end

  before_validation :assign_reference_code, on: :create
  before_validation :clear_occurred_at_unless_backdated
  before_validation :normalize_disaster_incident_type
  # Group-chat notifications (LINE/Telegram/Signal/webhook); bulk-imported incidents are not announced.
  after_create :notify_channels, unless: -> { self[:imported_dataset_id].present? }

  scope :visible_to, lambda { |user|
    visible = where(deleted_at: nil)
    user.system_admin? ? visible : visible.any_of(
      { :owner_user_id.in => user.organization_user_ids },
      { owner_user_id: nil, :subdistrict_id.in => user.accessible_subdistrict_ids }
    )
  }

  # Reported incidents and disasters, excluding planned activities.
  scope :incidents_only, -> { where(:category.ne => "activity") }
  scope :activities, -> { where(category: "activity") }

  # Activities finish on their own once ends_at passes; called by the periodic worker and before activity reads.
  def self.finish_expired_activities!(now = Time.current)
    activities.where(deleted_at: nil, :status.ne => "completed", :ends_at.lte => now).each do |activity|
      activity.histories << {
        "title" => "สิ้นสุดกิจกรรม",
        "description" => activity.received_at ? "สิ้นสุดอัตโนมัติตามเวลาที่กำหนด" : "สิ้นสุดอัตโนมัติตามเวลาที่กำหนด (ยังไม่มีผู้รับเรื่อง)",
        "occurred_at" => activity.ends_at.utc.iso8601,
        "actor" => "ระบบ",
        "resources" => []
      }
      activity.status = "completed"
      activity.save!(validate: false)
    end
  end

  def activity? = category == "activity"
  def activity_type_label = ACTIVITY_TYPES.dig(incident_type, :label) || incident_type
  def activity_icon = ACTIVITY_TYPES.dig(incident_type, :icon) || "event"
  def cover_photo = Array(photos).find { |photo| photo["id"] == cover_photo_id }

  def activity_phase(now = Time.current)
    return "finished" if status == "completed" || (ends_at && ends_at <= now)
    return "ongoing" if starts_at && starts_at <= now

    "upcoming"
  end

  def activity_phase_label = ACTIVITY_PHASES.fetch(activity_phase)
  def activity_status_label
    return "สิ้นสุดแล้ว" if status == "completed"

    status == "pending" ? "รอรับเรื่อง" : "รับเรื่องแล้ว"
  end

  def report_source_label
    report_source_name.presence || (report_source_type == "citizen" ? "ประชาชน" : "เจ้าหน้าที่")
  end

  def active_plan
    response_plan_versions.find { |version| version["version"].to_i == active_plan_version.to_i }
  end

  def category_label
    { "disaster" => "แจ้งเตือนภัยพิบัติ", "activity" => "กิจกรรมในพื้นที่" }.fetch(category, "เหตุการณ์ทั่วไป")
  end

  private

  def notify_channels
    NotificationDispatchJob.perform_later(id.to_s)
  rescue StandardError => error
    Rails.logger.error("Could not queue incident notification: #{error.class}: #{error.message}")
  end

  def activity_must_end_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "ต้องอยู่หลังเวลาเริ่มต้น")
  end

  def assign_reference_code
    self.reference_code ||= "INC-#{Time.current.year + 543}-#{SecureRandom.hex(3).upcase}"
  end

  def clear_occurred_at_unless_backdated
    return if backdated?

    self.occurred_at = nil
  end

  def normalize_disaster_incident_type
    self.incident_type = "พายุ" if incident_type == "วาตภัย"
  end
end

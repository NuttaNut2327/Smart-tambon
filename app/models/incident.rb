class Incident
  include Mongoid::Document
  include Mongoid::Timestamps

  CATEGORIES = %w[disaster general].freeze
  DISASTER_INCIDENT_TYPES = ["น้ำท่วม", "ไฟป่า", "วาตภัย", "ภัยแล้ง", "อื่น ๆ"].freeze
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
  field :assigned_to, type: String
  field :received_by, type: String
  field :received_by_user_id, type: Integer
  field :received_at, type: Time
  field :histories, type: Array, default: []
  field :resources_used, type: Array, default: []
  field :response_plan_versions, type: Array, default: []
  field :active_plan_version, type: Integer
  field :deleted_at, type: Time
  field :deleted_by, type: String

  index({ subdistrict_id: 1, created_at: -1 })
  index({ owner_user_id: 1, report_source_name: 1, created_at: -1 })
  index({ category: 1, status: 1 })
  index({ reference_code: 1 }, { unique: true, sparse: true })

  validates :title, :category, :status, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :occurred_at, presence: true, if: :backdated?

  before_validation :assign_reference_code, on: :create
  before_validation :clear_occurred_at_unless_backdated

  scope :visible_to, lambda { |user|
    visible = where(deleted_at: nil)
    user.system_admin? ? visible : visible.any_of(
      { owner_user_id: user.id },
      { owner_user_id: nil, :subdistrict_id.in => user.accessible_subdistrict_ids }
    )
  }

  def report_source_label
    report_source_name.presence || (report_source_type == "citizen" ? "ประชาชน" : "เจ้าหน้าที่")
  end

  def active_plan
    response_plan_versions.find { |version| version["version"].to_i == active_plan_version.to_i }
  end

  def category_label
    category == "disaster" ? "แจ้งเตือนภัยพิบัติ" : "เหตุการณ์ทั่วไป"
  end

  private

  def assign_reference_code
    self.reference_code ||= "INC-#{Time.current.year + 543}-#{SecureRandom.hex(3).upcase}"
  end

  def clear_occurred_at_unless_backdated
    return if backdated?

    self.occurred_at = nil
  end
end

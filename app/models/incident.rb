class Incident
  include Mongoid::Document
  include Mongoid::Timestamps

  CATEGORIES = %w[disaster general].freeze
  DISASTER_INCIDENT_TYPES = ["น้ำท่วม", "ไฟป่า", "วาตภัย", "ภัยแล้ง", "อื่น ๆ"].freeze
  STATUSES = %w[pending assessing in_progress completed].freeze
  SEVERITIES = %w[watch urgent critical].freeze

  field :user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :reference_code, type: String
  field :category, type: String, default: "general"
  field :incident_type, type: String
  field :title, type: String
  field :description, type: String
  field :severity, type: String, default: "watch"
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

  index({ subdistrict_id: 1, created_at: -1 })
  index({ category: 1, status: 1 })
  index({ reference_code: 1 }, { unique: true, sparse: true })

  validates :title, :category, :status, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }

  before_validation :assign_reference_code, on: :create

  scope :visible_to, lambda { |user|
    user.system_admin? ? all : where(:subdistrict_id.in => user.accessible_subdistrict_ids)
  }

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
end

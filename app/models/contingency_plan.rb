class ContingencyPlan
  include Mongoid::Document
  include Mongoid::Timestamps

  DISASTER_TYPES = {
    "flood" => "น้ำท่วม", "fire" => "ไฟป่า", "wind" => "พายุ",
    "landslide" => "ดินถล่ม", "drought" => "ภัยแล้ง", "other" => "อื่น ๆ"
  }.freeze
  STATUSES = { "draft" => "ฉบับร่าง", "ready" => "พร้อมใช้งาน", "archived" => "เก็บถาวร" }.freeze

  field :organization_key, type: String
  field :user_id, type: Integer
  field :name, type: String
  field :description, type: String
  field :disaster_type, type: String, default: "flood"
  field :status, type: String, default: "draft"
  field :versions, type: Array, default: []
  field :active_version, type: Integer
  field :created_by, type: String
  field :updated_by, type: String

  index({ organization_key: 1, updated_at: -1 })

  validates :organization_key, :name, presence: true
  validates :disaster_type, inclusion: { in: DISASTER_TYPES.keys }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :visible_to, ->(user) { user.system_admin? ? all : where(organization_key: user.organization_key) }

  def disaster_type_label = DISASTER_TYPES.fetch(disaster_type, disaster_type)
  def status_label = STATUSES.fetch(status, status)
  def current_version
    versions.find { |item| item["version"].to_i == active_version.to_i } || versions.max_by { |item| item["version"].to_i }
  end
end

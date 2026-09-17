class ImportedDataset
  include Mongoid::Document
  include Mongoid::Timestamps

  STANDARD_SCHEMAS = {
    "population" => [
      { "key" => "subdistrict", "label" => "ตำบล", "type" => "text", "required" => true },
      { "key" => "village_number", "label" => "หมู่ที่", "type" => "integer", "required" => true },
      { "key" => "village_name", "label" => "หมู่บ้าน", "type" => "text", "required" => true },
      { "key" => "population_male", "label" => "ประชากรชาย", "type" => "integer", "required" => true },
      { "key" => "population_female", "label" => "ประชากรหญิง", "type" => "integer", "required" => true },
      { "key" => "population_total", "label" => "ประชากรทั้งหมด", "type" => "integer", "required" => true },
      { "key" => "household_count", "label" => "จำนวนครัวเรือน", "type" => "integer", "required" => true }
    ],
    "resources" => [
      { "key" => "name", "label" => "ชื่อทรัพยากร/อุปกรณ์", "type" => "text", "required" => true },
      { "key" => "code", "label" => "รหัส", "type" => "text", "required" => false },
      { "key" => "registration", "label" => "ทะเบียน", "type" => "text", "required" => false },
      { "key" => "resource_type", "label" => "ประเภท", "type" => "text", "required" => true },
      { "key" => "status", "label" => "สถานะ", "type" => "text", "required" => false },
      { "key" => "storage_location", "label" => "สถานที่เก็บ", "type" => "text", "required" => false },
      { "key" => "responsible_person", "label" => "ผู้รับผิดชอบ", "type" => "text", "required" => false }
    ],
    "workforce" => [
      { "key" => "team_name", "label" => "ชื่อทีม", "type" => "text", "required" => true },
      { "key" => "duty", "label" => "หน้าที่", "type" => "text", "required" => true },
      { "key" => "member_count", "label" => "จำนวนสมาชิก", "type" => "integer", "required" => true },
      { "key" => "ready_count", "label" => "พร้อมปฏิบัติงาน", "type" => "integer", "required" => true },
      { "key" => "responsible_area", "label" => "พื้นที่รับผิดชอบ", "type" => "text", "required" => true },
      { "key" => "team_leader", "label" => "หัวหน้าทีม", "type" => "text", "required" => true }
    ]
  }.freeze
  TYPE_LABELS = { "population" => "ข้อมูลประชากร", "resources" => "ข้อมูลทรัพยากรและอุปกรณ์", "workforce" => "ข้อมูลทีมงานและกำลังคน", "custom" => "ชุดข้อมูลแบบกำหนดเอง" }.freeze
  CUSTOM_CATEGORY_LABELS = { "population" => "ข้อมูลประชากร", "resources" => "ข้อมูลทรัพยากรและอุปกรณ์",
    "workforce" => "ข้อมูลทีมงานและกำลังคน", "area" => "ข้อมูลพื้นที่" }.freeze
  GEOMETRY_TYPES = %w[none point line polygon].freeze
  FIELD_TYPES = %w[text number integer date boolean].freeze

  field :user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :name, type: String
  field :data_type, type: String
  field :data_category, type: String
  field :geometry_type, type: String, default: "none"
  field :schema_definition, type: Array, default: []
  field :map_enabled, type: Boolean, default: false
  field :shared_with_all, type: Boolean, default: false
  field :current_version_id, type: BSON::ObjectId
  has_many :versions, class_name: "ImportedDatasetVersion", dependent: :destroy
  index({ user_id: 1 }); index({ subdistrict_id: 1 }); index({ data_type: 1 }); index({ map_enabled: 1 })
  validates :user_id, :name, presence: true
  validates :data_type, inclusion: { in: TYPE_LABELS.keys }
  validates :data_category, inclusion: { in: CUSTOM_CATEGORY_LABELS.keys }, allow_blank: true
  validates :geometry_type, inclusion: { in: GEOMETRY_TYPES }
  validate :valid_schema_definition
  validate :map_geometry_is_usable

  scope :visible_to, ->(user) { user.system_admin? ? all : any_of({ user_id: user.id }, { shared_with_all: true, subdistrict_id: { "$in" => user.accessible_subdistrict_ids } }) }

  def user = User.find_by(id: user_id)
  def user=(value)
    self.user_id = value&.id
  end
  def subdistrict = Subdistrict.find_by(id: subdistrict_id)
  def subdistrict=(value)
    self.subdistrict_id = value&.id
  end
  def current_version = current_version_id && versions.where(id: current_version_id).first
  def current_version=(value)
    self.current_version_id = value&.id
  end
  def type_label = TYPE_LABELS.fetch(data_type)
  def category_label = CUSTOM_CATEGORY_LABELS[data_category] || "ยังไม่ระบุประเภท"
  def record_count = current_version&.record_count.to_i
  def self.schema_for(type) = STANDARD_SCHEMAS[type]&.deep_dup
  def effective_schema_definition = self.class.schema_for(data_type) || schema_definition

  private

  def valid_schema_definition
    fields = Array(schema_definition)
    errors.add(:schema_definition, "ต้องมีอย่างน้อย 1 คอลัมน์") if fields.empty?
    errors.add(:schema_definition, "มีคอลัมน์ได้ไม่เกิน 50 คอลัมน์") if fields.size > 50
    keys = fields.map { |field| field["key"].to_s }
    errors.add(:schema_definition, "ชื่อคอลัมน์ต้องไม่ซ้ำกัน") unless keys.uniq.size == keys.size
    errors.add(:schema_definition, "ชื่อคอลัมน์ไม่ถูกต้อง") unless keys.all? { |key| key.match?(/\A[a-z][a-z0-9_]*\z/) }
    errors.add(:schema_definition, "ชื่อหัวข้อห้ามว่าง") unless fields.all? { |field| field["label"].present? }
    errors.add(:schema_definition, "ชนิดข้อมูลไม่ถูกต้อง") unless fields.all? { |field| FIELD_TYPES.include?(field["type"]) }
  end

  def map_geometry_is_usable
    return unless map_enabled?
    keys = Array(schema_definition).map { |field| field["key"] }
    errors.add(:geometry_type, "กรุณาเลือกรูปแบบตำแหน่งบนแผนที่") if geometry_type == "none"
    return unless geometry_type == "point"

    errors.add(:schema_definition, "ต้องมีคอลัมน์ latitude และ longitude") unless %w[latitude longitude].all? { |key| keys.include?(key) }
  end
end

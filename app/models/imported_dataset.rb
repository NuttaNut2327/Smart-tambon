class ImportedDataset
  include Mongoid::Document
  include Mongoid::Timestamps

  STANDARD_SCHEMAS = {
    "population" => [
      { "key" => "subdistrict_code", "label" => "รหัสตำบล", "type" => "text", "required" => false },
      { "key" => "subdistrict", "label" => "ตำบล", "type" => "text", "required" => true },
      { "key" => "village_code", "label" => "รหัสหมู่บ้าน", "type" => "text", "required" => false },
      { "key" => "village_number", "label" => "หมู่ที่", "type" => "integer", "required" => true },
      { "key" => "village_name", "label" => "หมู่บ้าน", "type" => "text", "required" => true },
      { "key" => "population_male", "label" => "ประชากรชาย", "type" => "integer", "required" => true },
      { "key" => "population_female", "label" => "ประชากรหญิง", "type" => "integer", "required" => true },
      { "key" => "population_total", "label" => "ประชากรทั้งหมด", "type" => "integer", "required" => true },
      { "key" => "household_count", "label" => "จำนวนครัวเรือน", "type" => "integer", "required" => true },
      { "key" => "boundary_status", "label" => "สถานะขอบเขต", "type" => "text", "required" => false, "generated" => true },
      { "key" => "boundary_dataset_id", "label" => "ชุดข้อมูลขอบเขต", "type" => "text", "required" => false, "generated" => true, "hidden" => true },
      { "key" => "boundary_record_position", "label" => "ลำดับขอบเขต", "type" => "integer", "required" => false, "generated" => true, "hidden" => true }
    ],
    "village_boundaries" => [
      { "key" => "subdistrict_code", "label" => "รหัสตำบล", "type" => "text", "required" => false },
      { "key" => "subdistrict", "label" => "ตำบล", "type" => "text", "required" => true },
      { "key" => "village_code", "label" => "รหัสหมู่บ้าน", "type" => "text", "required" => false },
      { "key" => "village_number", "label" => "หมู่ที่", "type" => "integer", "required" => true },
      { "key" => "village_name", "label" => "หมู่บ้าน", "type" => "text", "required" => true },
      { "key" => "geometry", "label" => "ขอบเขต (GeoJSON)", "type" => "text", "required" => true, "hidden" => true },
      { "key" => "boundary_source", "label" => "วิธีบันทึก", "type" => "text", "required" => false, "generated" => true }
    ],
    "resources" => [
      { "key" => "name", "label" => "ชื่อทรัพยากร/อุปกรณ์", "type" => "text", "required" => true },
      { "key" => "code", "label" => "รหัสทรัพยากร", "type" => "text", "required" => false, "generated" => true },
      { "key" => "registration", "label" => "ทะเบียน", "type" => "text", "required" => false },
      { "key" => "resource_type", "label" => "ประเภท", "type" => "text", "required" => true },
      { "key" => "status", "label" => "สถานะความพร้อม", "type" => "text", "required" => true },
      { "key" => "responsible_person", "label" => "หน่วยงานผู้รับผิดชอบ", "type" => "text", "required" => true },
      { "key" => "agency_code", "label" => "รหัสหน่วยงาน", "type" => "text", "required" => true, "hidden" => true },
      { "key" => "storage_location", "label" => "สถานที่เก็บ", "type" => "text", "required" => false }
    ],
    "consumables" => [
      { "key" => "consumable_code", "label" => "รหัสวัสดุ", "type" => "text", "required" => false, "generated" => true },
      { "key" => "name", "label" => "ชื่อวัสดุสิ้นเปลือง", "type" => "text", "required" => true },
      { "key" => "category", "label" => "ประเภท", "type" => "text", "required" => true },
      { "key" => "unit", "label" => "หน่วยนับ", "type" => "text", "required" => true },
      { "key" => "agency_code", "label" => "รหัสหน่วยงาน", "type" => "text", "required" => true, "hidden" => true },
      { "key" => "agency_name", "label" => "หน่วยงานผู้รับผิดชอบ", "type" => "text", "required" => true },
      { "key" => "storage_location", "label" => "สถานที่เก็บ", "type" => "text", "required" => false },
      { "key" => "current_quantity", "label" => "จำนวนคงเหลือ", "type" => "number", "required" => true },
      { "key" => "minimum_quantity", "label" => "จุดแจ้งเตือนขั้นต่ำ", "type" => "number", "required" => false }
    ],
    "workforce" => [
      { "key" => "personnel_code", "label" => "รหัสบุคลากร", "type" => "text", "required" => false, "generated" => true },
      { "key" => "full_name", "label" => "ชื่อ–นามสกุล", "type" => "text", "required" => true },
      { "key" => "position", "label" => "ตำแหน่ง/หน้าที่", "type" => "text", "required" => true },
      { "key" => "skills", "label" => "ทักษะ", "type" => "text", "required" => false },
      { "key" => "agency_code", "label" => "รหัสหน่วยงาน", "type" => "text", "required" => true, "hidden" => true },
      { "key" => "agency_name", "label" => "หน่วยงาน", "type" => "text", "required" => true },
      { "key" => "team_code", "label" => "รหัสทีม", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "team_name", "label" => "ทีมปฏิบัติงาน", "type" => "text", "required" => false },
      { "key" => "employment_status", "label" => "สถานะบุคลากร", "type" => "text", "required" => true },
      { "key" => "availability_status", "label" => "ความพร้อมปฏิบัติงาน", "type" => "text", "required" => true },
      { "key" => "phone", "label" => "เบอร์ติดต่อ", "type" => "text", "required" => false }
    ],
    "teams" => [
      { "key" => "team_code", "label" => "รหัสทีม", "type" => "text", "required" => false, "generated" => true },
      { "key" => "team_name", "label" => "ชื่อทีม", "type" => "text", "required" => true },
      { "key" => "agency_code", "label" => "รหัสหน่วยงาน", "type" => "text", "required" => true, "hidden" => true },
      { "key" => "agency_name", "label" => "หน่วยงานต้นสังกัด", "type" => "text", "required" => true },
      { "key" => "team_type", "label" => "ประเภททีม", "type" => "text", "required" => true },
      { "key" => "leader_name", "label" => "หัวหน้าทีม", "type" => "text", "required" => false },
      { "key" => "responsible_area", "label" => "พื้นที่รับผิดชอบ", "type" => "text", "required" => false },
      { "key" => "status", "label" => "สถานะทีม", "type" => "text", "required" => true }
    ],
    "agencies" => [
      { "key" => "agency_code", "label" => "รหัสหน่วยงาน", "type" => "text", "required" => false, "generated" => true },
      { "key" => "agency_name", "label" => "ชื่อหน่วยงาน", "type" => "text", "required" => true },
      { "key" => "agency_type", "label" => "ประเภทหน่วยงาน", "type" => "text", "required" => true },
      { "key" => "contact_person", "label" => "ผู้ประสานงาน", "type" => "text", "required" => false },
      { "key" => "phone", "label" => "เบอร์ติดต่อ", "type" => "text", "required" => false },
      { "key" => "email", "label" => "อีเมล", "type" => "text", "required" => false },
      { "key" => "address", "label" => "ที่อยู่โดยประมาณ", "type" => "text", "required" => false },
      { "key" => "road", "label" => "ถนน", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "subdistrict", "label" => "ตำบล", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "district", "label" => "อำเภอ", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "province", "label" => "จังหวัด", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "postcode", "label" => "รหัสไปรษณีย์", "type" => "text", "required" => false, "hidden" => true },
      { "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => true, "hidden" => true },
      { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => true, "hidden" => true }
    ],
    "incidents" => [
      { "key" => "reference_code", "label" => "รหัสเหตุการณ์", "type" => "text", "required" => false, "generated" => true },
      { "key" => "title", "label" => "ชื่อเหตุการณ์", "type" => "text", "required" => true },
      { "key" => "incident_type", "label" => "ประเภทเหตุการณ์", "type" => "text", "required" => true },
      { "key" => "severity", "label" => "ระดับความรุนแรง", "type" => "text", "required" => true },
      { "key" => "status", "label" => "สถานะ", "type" => "text", "required" => false, "generated" => true },
      { "key" => "occurred_at", "label" => "วันและเวลาเกิดเหตุ", "type" => "text", "required" => true },
      { "key" => "description", "label" => "รายละเอียด", "type" => "text", "required" => false },
      { "key" => "reporter_name", "label" => "ผู้แจ้งเหตุ", "type" => "text", "required" => false },
      { "key" => "reporter_contact", "label" => "เบอร์ติดต่อ", "type" => "text", "required" => false },
      { "key" => "location_name", "label" => "ชื่อสถานที่เกิดเหตุ", "type" => "text", "required" => false },
      { "key" => "initial_impact", "label" => "ผลกระทบเบื้องต้น", "type" => "text", "required" => false },
      { "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => true },
      { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => true }
    ]
  }.freeze
  TYPE_LABELS = { "population" => "ข้อมูลประชากร", "village_boundaries" => "ขอบเขตหมู่บ้าน", "resources" => "ข้อมูลทรัพยากรและอุปกรณ์", "consumables" => "วัสดุสิ้นเปลือง", "workforce" => "บุคลากรปฏิบัติงาน", "teams" => "ทีมปฏิบัติงาน", "agencies" => "หน่วยงาน", "incidents" => "แจ้งเหตุการณ์", "custom" => "ชุดข้อมูลแบบกำหนดเอง" }.freeze
  CUSTOM_CATEGORY_LABELS = { "population" => "ข้อมูลประชากร", "resources" => "ข้อมูลทรัพยากรและอุปกรณ์",
    "workforce" => "บุคลากรปฏิบัติงาน", "area" => "ข้อมูลพื้นที่" }.freeze
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

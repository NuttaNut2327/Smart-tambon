# A message template owned by one อบต.: a name, the tag (event) it is used for, and a body with {{variables}}.
# When an event fires, the most recently updated template with that tag is used; without one, DEFAULTS apply.
class NotificationTemplate
  include Mongoid::Document
  include Mongoid::Timestamps

  # Contact details of the reporter are deliberately not offered: group chats sit outside the app's access control.
  VARIABLES = {
    "system_name" => "ชื่อระบบ", "organization_name" => "ชื่อหน่วยงาน (อบต.)",
    "reference_code" => "เลขที่เรื่อง", "category" => "หมวด (เหตุการณ์/ภัยพิบัติ/กิจกรรม)", "incident_type" => "ประเภท",
    "title" => "หัวข้อ", "description" => "รายละเอียด (ตัดที่ 500 ตัวอักษร)", "severity" => "ความเร่งด่วน", "status" => "สถานะ",
    "report_source" => "ช่องทางแจ้ง", "location_name" => "สถานที่", "subdistrict" => "ตำบล",
    "latitude" => "ละติจูด", "longitude" => "ลองจิจูด", "map_url" => "ลิงก์แผนที่ (Google Maps)",
    "affected_people" => "ผู้ได้รับผลกระทบ (คน)", "affected_households" => "ครัวเรือนที่ได้รับผลกระทบ",
    "activity_starts_at" => "วันเวลาเริ่มกิจกรรม", "activity_ends_at" => "วันเวลาสิ้นสุดกิจกรรม",
    "reported_at" => "วันเวลาที่แจ้ง", "link" => "ลิงก์เปิดเรื่องในระบบ", "message" => "ข้อความ (ใช้กับแท็กประกาศ)"
  }.freeze

  CITIZEN_ONLY_VARIABLES = {
    "reporter_name" => "ชื่อผู้แจ้ง", "reporter_contact" => "เบอร์ติดต่อผู้แจ้ง",
    "initial_impact" => "ผลกระทบเบื้องต้นที่ผู้แจ้งระบุ"
  }.freeze
  # Details supplied by the reporter for their own incident. Internal links, assignments and resources stay hidden.
  CITIZEN_VARIABLES = VARIABLES.slice(
    "organization_name", "reference_code", "category", "title", "description", "incident_type", "severity", "status",
    "report_source", "location_name", "subdistrict", "latitude", "longitude", "map_url", "reported_at"
  ).merge(CITIZEN_ONLY_VARIABLES).freeze
  CITIZEN_TAGS = {
    "citizen.submitted" => "ประชาชนส่งเรื่องเข้าสู่ระบบแล้ว",
    "citizen.acknowledged" => "เจ้าหน้าที่รับเรื่องแล้ว",
    "citizen.completed" => "ดำเนินการเสร็จสิ้นแล้ว"
  }.freeze
  TAGS = NotificationChannel::TAGS.merge(CITIZEN_TAGS).freeze
  TAG_GROUPS = {
    "ข้อความแจ้งความคืบหน้าสำหรับประชาชน" => CITIZEN_TAGS,
    "ข้อความแจ้งเตือนสำหรับกลุ่มเจ้าหน้าที่" => NotificationChannel::TAGS
  }.freeze

  DEFAULTS = {
    "incident.created" => <<~TEXT.strip,
      🔔 มีเหตุการณ์แจ้งเข้ามาใหม่
      เลขที่: {{reference_code}}
      เรื่อง: {{title}}
      ประเภท: {{incident_type}} · ความเร่งด่วน: {{severity}}
      สถานที่: {{location_name}} ต.{{subdistrict}}
      แจ้งโดย: {{report_source}} · {{reported_at}}
      แผนที่: {{map_url}}
      เปิดในระบบ: {{link}}
    TEXT
    "disaster.created" => <<~TEXT.strip,
      🚨 แจ้งเตือนภัยพิบัติ: {{incident_type}}
      เลขที่: {{reference_code}}
      เรื่อง: {{title}}
      ความเร่งด่วน: {{severity}} · ผู้ได้รับผลกระทบ {{affected_people}} คน / {{affected_households}} ครัวเรือน
      สถานที่: {{location_name}} ต.{{subdistrict}}
      เวลา: {{reported_at}}
      แผนที่: {{map_url}}
      เปิดในระบบ: {{link}}
    TEXT
    "activity.created" => <<~TEXT.strip,
      📅 กิจกรรมใหม่ในพื้นที่: {{title}}
      ประเภท: {{incident_type}}
      วันที่: {{activity_starts_at}} – {{activity_ends_at}}
      สถานที่: {{location_name}}
      เปิดในระบบ: {{link}}
    TEXT
    "announcement" => "📢 {{organization_name}}\n{{message}}",
    "citizen.submitted" => "ระบบได้รับเรื่องของคุณแล้ว\nเลขอ้างอิง: {{reference_code}}\nเรื่อง: {{title}}",
    "citizen.acknowledged" => "เจ้าหน้าที่รับเรื่องแล้ว\nเลขอ้างอิง: {{reference_code}}\nเรื่อง: {{title}}",
    "citizen.completed" => "ดำเนินการเสร็จสิ้นแล้ว\nเลขอ้างอิง: {{reference_code}}\nเรื่อง: {{title}}"
  }.freeze

  field :organization_key, type: String
  field :name, type: String
  field :tag, type: String
  field :body, type: String
  field :active, type: Boolean, default: false
  field :updated_by, type: String

  index({ organization_key: 1, tag: 1, updated_at: -1 })

  validates :organization_key, :name, :body, presence: true
  validates :tag, inclusion: { in: TAGS.keys }
  validates :body, length: { maximum: 3000 }
  validate :variables_must_be_known
  before_create :activate_if_first_for_tag

  scope :for_organization, ->(key) { where(organization_key: key) }

  def self.body_for(organization_key, tag)
    scope = for_organization(organization_key).where(tag: tag)
    (scope.where(active: true).desc(:updated_at).first || scope.desc(:updated_at).first)&.body || DEFAULTS.fetch(tag, "{{title}}")
  end

  def tag_label = TAGS.fetch(tag, tag)
  def citizen? = CITIZEN_TAGS.key?(tag)
  def available_variables = citizen? ? CITIZEN_VARIABLES : VARIABLES
  def unknown_variables = body.to_s.scan(/\{\{\s*([a-z_]+)\s*\}\}/).flatten.uniq - available_variables.keys

  private

  def activate_if_first_for_tag
    self.active = true unless self.class.for_organization(organization_key).where(tag: tag).exists?
  end

  def variables_must_be_known
    errors.add(:body, "มีตัวแปรที่ไม่รู้จัก: #{unknown_variables.map { |name| "{{#{name}}}" }.join(', ')}") if unknown_variables.any?
  end
end

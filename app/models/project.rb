class Project
  include Mongoid::Document
  include Mongoid::Timestamps

  # Group => suggested project types. Types are free text so local agencies can add their own.
  GROUPS = {
    "infrastructure" => { label: "โครงสร้างพื้นฐาน", types: ["ถนน", "สะพาน", "ท่อระบายน้ำ", "ไฟฟ้าส่องสว่าง", "ประปา", "อาคาร/สิ่งก่อสร้าง"] },
    "water" => { label: "แหล่งน้ำและการเกษตร", types: ["ขุดลอกคลอง", "ฝาย", "สระเก็บน้ำ", "ระบบชลประทาน", "ส่งเสริมการเกษตร"] },
    "economy" => { label: "เศรษฐกิจและอาชีพ", types: ["ฝึกอาชีพ", "วิสาหกิจชุมชน", "ตลาดชุมชน", "ท่องเที่ยวชุมชน"] },
    "social" => { label: "สังคมและคุณภาพชีวิต", types: ["ผู้สูงอายุ", "ผู้พิการ", "เด็กและเยาวชน", "กีฬาและนันทนาการ", "ศาสนาและวัฒนธรรม"] },
    "health" => { label: "สาธารณสุข", types: ["ป้องกันโรค", "ส่งเสริมสุขภาพ", "สถานพยาบาล", "ควบคุมโรคติดต่อ"] },
    "education" => { label: "การศึกษา", types: ["ศูนย์พัฒนาเด็กเล็ก", "อาหารกลางวัน/อาหารเสริม", "อุปกรณ์การเรียน", "ห้องสมุด/แหล่งเรียนรู้"] },
    "environment" => { label: "ทรัพยากรธรรมชาติและสิ่งแวดล้อม", types: ["จัดการขยะ", "ปลูกป่า", "บำบัดน้ำเสีย", "พลังงานทดแทน"] },
    "safety" => { label: "ความปลอดภัยและป้องกันภัย", types: ["ป้องกันและบรรเทาสาธารณภัย", "กล้องวงจรปิด", "ความปลอดภัยทางถนน", "ยาเสพติด"] },
    "administration" => { label: "การบริหารจัดการ", types: ["ครุภัณฑ์", "ระบบสารสนเทศ", "พัฒนาบุคลากร", "จัดเก็บรายได้"] },
    "other" => { label: "อื่น ๆ", types: [] }
  }.freeze
  # Budget approval is tracked separately from implementation status; the budget chart stacks by it.
  APPROVAL_STATUSES = {
    "approved" => "อนุมัติ",
    "pending" => "รอพิจารณา",
    "rejected" => "ไม่อนุมัติ"
  }.freeze
  STATUSES = {
    "planned" => "วางแผน/รออนุมัติ",
    "procurement" => "จัดซื้อจัดจ้าง",
    "in_progress" => "กำลังดำเนินการ",
    "completed" => "ดำเนินการแล้วเสร็จ",
    "suspended" => "ชะลอ/ยกเลิก"
  }.freeze

  field :user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :name, type: String
  field :code, type: String
  field :group, type: String
  field :project_type, type: String
  field :budget, type: Float
  field :budget_source, type: String
  field :agency, type: String
  field :fiscal_year, type: Integer
  field :status, type: String, default: "planned"
  field :approval_status, type: String, default: "pending"
  field :progress_percent, type: Integer, default: 0
  field :location_name, type: String
  field :description, type: String
  field :latitude, type: Float
  field :longitude, type: Float
  field :photos, type: Array, default: []
  # Demo record: hidden everywhere while demo data is switched off (see DemoData).
  field :simulated, type: Boolean, default: false

  index({ user_id: 1, updated_at: -1 })
  index({ subdistrict_id: 1, fiscal_year: -1 })
  index({ group: 1, status: 1 })

  # Set by the controller so location can be checked against the editor's area.
  attr_accessor :acting_user

  before_validation :normalize_fields
  before_validation :assign_subdistrict

  validates :user_id, :name, :group, :project_type, :agency, :fiscal_year, presence: true
  validates :group, inclusion: { in: GROUPS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES.keys }
  validates :budget, numericality: { greater_than_or_equal_to: 0, message: "ต้องไม่ติดลบ" }, allow_nil: true
  validates :fiscal_year, numericality: { only_integer: true, greater_than_or_equal_to: 2500, less_than_or_equal_to: 2700, message: "ต้องเป็นปี พ.ศ. เช่น 2570" }, allow_nil: true
  validates :progress_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90, message: "ต้องอยู่ระหว่าง -90 ถึง 90" }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180, message: "ต้องอยู่ระหว่าง -180 ถึง 180" }, allow_nil: true
  validate :coordinates_must_be_paired
  validate :location_must_be_inside_acting_user_area

  scope :visible_to, lambda { |user|
    DemoData.filter(user.system_admin? ? all : any_of(
      { :user_id.in => user.organization_user_ids },
      { :subdistrict_id.in => user.accessible_subdistrict_ids }
    ))
  }

  # Thai fiscal year (พ.ศ.) starts on 1 October.
  def self.current_fiscal_year(date = Date.current)
    date.year + 543 + (date.month >= 10 ? 1 : 0)
  end

  def self.group_label(key) = GROUPS.dig(key, :label) || key

  def group_label = self.class.group_label(group)
  def status_label = STATUSES.fetch(status, status)
  def approval_status_label = APPROVAL_STATUSES.fetch(approval_status, approval_status)
  def located? = latitude.present? && longitude.present?
  def subdistrict = subdistrict_id && Subdistrict.find_by(id: subdistrict_id)

  def as_map_json(photo_url: nil)
    area = subdistrict
    {
      id: id.to_s, name:, code:, simulated:, group:, group_label:, project_type:,
      budget:, budget_source:, agency:, fiscal_year:,
      status:, status_label:, approval_status:, approval_status_label:, progress_percent:,
      location_name:, description:, latitude:, longitude:,
      subdistrict_name: area&.name_th, district_name: area&.district_name_th,
      photos: Array(photos).map do |photo|
        { id: photo["id"], filename: photo["filename"], url: photo_url&.call(self, photo), thumb: photo_url&.call(self, photo, "thumb") }
      end
    }
  end

  private

  def normalize_fields
    %i[name code project_type budget_source agency location_name description].each { |name| self[name] = self[name].to_s.strip.presence }
    self.progress_percent = 100 if status == "completed" && progress_percent.to_i < 100
  end

  def assign_subdistrict
    if located?
      return unless new_record? || latitude_changed? || longitude_changed? || subdistrict_id.blank?

      self.subdistrict_id = Subdistrict.where(
        "ST_Covers(boundary::geometry, ST_SetSRID(ST_Point(?, ?), 4326))", longitude.to_f, latitude.to_f
      ).pick(:id)
    elsif subdistrict_id.blank?
      # Projects without a map point still belong to the creator's area.
      self.subdistrict_id = acting_user&.subdistrict_id
    end
  end

  def coordinates_must_be_paired
    return if latitude.present? == longitude.present?

    errors.add(:base, "กรุณาระบุทั้งละติจูดและลองจิจูด หรือเว้นว่างทั้งคู่หากโครงการไม่มีจุดที่ตั้ง")
  end

  def location_must_be_inside_acting_user_area
    return if acting_user.nil? || acting_user.system_admin? || !located?
    return unless latitude.to_f.between?(-90, 90) && longitude.to_f.between?(-180, 180)
    return if subdistrict_id.present? && acting_user.accessible_subdistrict_ids.include?(subdistrict_id)

    errors.add(:base, "ที่ตั้งโครงการอยู่นอกพื้นที่ที่คุณดูแล")
  end
end

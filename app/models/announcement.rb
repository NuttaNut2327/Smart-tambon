class Announcement
  include Mongoid::Document
  include Mongoid::Timestamps

  LEVELS = {
    "info" => "ข้อมูล",
    "warning" => "เตือน",
    "urgent" => "ด่วน"
  }.freeze
  # once: until the user acknowledges (or, for corner boxes, after the first session it was shown in).
  # always: every login/session until the announcement expires or is deactivated.
  FREQUENCIES = {
    "once" => "แสดงครั้งเดียวต่อผู้ใช้",
    "always" => "แสดงทุกครั้งจนกว่าจะหมดอายุ/ปิดใช้งาน"
  }.freeze
  DISPLAY_MODES = {
    "dismissible" => "Popup กลางจอ มีปุ่มรับทราบ/ปิด",
    "corner" => "กล่องเล็กมุมจอ ปิดไม่ได้"
  }.freeze
  ROLES = {
    "system_admin" => "ผู้ดูแลระบบ",
    "subdistrict_admin" => "ผู้ดูแลประจำ อบต.",
    "subdistrict_user" => "เจ้าหน้าที่ประจำ อบต."
  }.freeze

  field :title, type: String
  field :body, type: String
  field :level, type: String, default: "info"
  field :frequency, type: String, default: "once"
  field :display_mode, type: String, default: "dismissible"
  field :active, type: Boolean, default: true
  field :starts_at, type: Time
  field :ends_at, type: Time
  # Empty arrays mean "everyone"; both filters must match when set.
  field :target_roles, type: Array, default: []
  field :target_subdistrict_ids, type: Array, default: []
  field :created_by_id, type: Integer

  has_many :receipts, class_name: "AnnouncementReceipt", dependent: :delete_all

  index({ active: 1, starts_at: 1, ends_at: 1 })

  # Form helper: subdistrict codes typed by the admin, resolved to ids on save.
  attr_writer :target_subdistrict_codes

  before_validation :normalize_fields

  validates :title, :body, presence: true
  validates :level, inclusion: { in: LEVELS.keys }
  validates :frequency, inclusion: { in: FREQUENCIES.keys }
  validates :display_mode, inclusion: { in: DISPLAY_MODES.keys }
  validate :ends_after_start
  validate :roles_are_known
  validate :subdistrict_codes_exist

  scope :current, lambda { |time = Time.current|
    where(active: true).and(
      { "$or" => [{ starts_at: nil }, { :starts_at.lte => time }] },
      { "$or" => [{ ends_at: nil }, { :ends_at.gte => time }] }
    )
  }

  def self.for_user(user, time = Time.current)
    current(time).to_a
      .select { |announcement| announcement.targets?(user) }
      .sort_by { |announcement| [-LEVELS.keys.index(announcement.level).to_i, -announcement.created_at.to_i] }
  end

  def targets?(user)
    return false if target_roles.any? && !target_roles.include?(user.role)
    return true if target_subdistrict_ids.empty?

    (target_subdistrict_ids.map(&:to_i) & user.accessible_subdistrict_ids).any?
  end

  def level_label = LEVELS.fetch(level, level)
  def frequency_label = FREQUENCIES.fetch(frequency, frequency)
  def display_mode_label = DISPLAY_MODES.fetch(display_mode, display_mode)
  def once? = frequency == "once"
  def corner? = display_mode == "corner"

  def status_label(time = Time.current)
    return "ปิดใช้งาน" unless active?
    return "รอเริ่ม" if starts_at && starts_at > time
    return "หมดอายุ" if ends_at && ends_at < time

    "กำลังแสดง"
  end

  def target_subdistricts = Subdistrict.where(id: target_subdistrict_ids).order(:code)

  def target_subdistrict_codes
    @target_subdistrict_codes || target_subdistricts.pluck(:code).join(", ")
  end

  def audience_label
    roles = target_roles.any? ? target_roles.map { |role| ROLES.fetch(role, role) }.join(", ") : "ทุกสิทธิ์"
    areas = target_subdistrict_ids.any? ? target_subdistricts.map { |area| "ต.#{area.name_th}" }.join(", ") : "ทุกพื้นที่"
    "#{roles} · #{areas}"
  end

  private

  def normalize_fields
    self.title = title.to_s.strip.presence
    self.body = body.to_s.strip.presence
    self.target_roles = Array(target_roles).compact_blank.uniq
    return if @target_subdistrict_codes.nil?

    @unknown_codes = []
    codes = @target_subdistrict_codes.to_s.split(/[\s,]+/).compact_blank.uniq
    found = Subdistrict.where(code: codes).pluck(:code, :id).to_h
    @unknown_codes = codes - found.keys
    self.target_subdistrict_ids = found.values
  end

  def ends_after_start
    return unless starts_at && ends_at && ends_at < starts_at

    errors.add(:ends_at, "ต้องอยู่หลังวันที่เริ่มแสดง")
  end

  def roles_are_known
    unknown = target_roles - ROLES.keys
    errors.add(:target_roles, "ไม่ถูกต้อง: #{unknown.join(', ')}") if unknown.any?
  end

  def subdistrict_codes_exist
    errors.add(:base, "ไม่พบรหัสตำบล: #{@unknown_codes.join(', ')}") if @unknown_codes.present?
  end
end

# A self-service application from a local government (อบต./เทศบาล) to join the system. The wizard fills it step by
# step (area → organisation → admin account → consent → OTP), then a system admin approves or rejects it.
# The admin's password is stored only as a bcrypt digest; the account is created on approval.
class OrganizationRegistration
  include Mongoid::Document
  include Mongoid::Timestamps

  STEPS = %w[area organization account consent verify].freeze
  STEP_LABELS = { "area" => "เลือกพื้นที่", "organization" => "ข้อมูลหน่วยงาน", "account" => "บัญชีผู้ดูแล", "consent" => "ข้อตกลงและ PDPA", "verify" => "ยืนยันตัวตน" }.freeze
  STATUSES = { "draft" => "กำลังกรอก", "pending_review" => "รออนุมัติ", "approved" => "อนุมัติแล้ว", "rejected" => "ไม่อนุมัติ" }.freeze
  OTP_CHANNELS = { "email" => "อีเมล", "sms" => "SMS" }.freeze
  USERNAME_FORMAT = /\A[a-z0-9._-]{4,32}\z/

  field :token, type: String
  field :status, type: String, default: "draft"
  field :step, type: String, default: "area"
  field :subdistrict_id, type: Integer
  field :organization_type, type: String, default: "subdistrict_administrative_organization"
  field :organization_name, type: String
  field :office_phone, type: String
  field :address, type: String
  field :admin_full_name, type: String
  field :admin_position, type: String
  field :username, type: String
  field :email, type: String
  field :phone, type: String
  field :password_digest, type: String
  field :terms_version, type: String
  field :pdpa_version, type: String
  field :consented_at, type: Time
  field :marketing_consent, type: Boolean, default: false
  field :otp_channel, type: String
  field :otp_target, type: String
  field :otp_code_digest, type: String
  field :otp_provider_token, type: String
  field :otp_ref, type: String
  field :otp_expires_at, type: Time
  field :otp_attempts, type: Integer, default: 0
  field :otp_sends, type: Integer, default: 0
  field :otp_last_sent_at, type: Time
  field :verified_at, type: Time
  field :submitted_at, type: Time
  field :reviewed_by, type: String
  field :reviewed_at, type: Time
  field :reject_reason, type: String
  field :user_id, type: Integer
  field :ip, type: String
  field :user_agent, type: String

  index({ token: 1 }, unique: true)
  index({ status: 1, submitted_at: -1 })
  index({ subdistrict_id: 1, status: 1 })
  index({ ip: 1, created_at: -1 })

  validates :token, presence: true
  validates :status, inclusion: { in: STATUSES.keys }

  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }

  scope :open, -> { where(:status.in => %w[draft pending_review]) }
  scope :pending, -> { where(status: "pending_review") }

  def subdistrict = subdistrict_id && Subdistrict.includes(:province).find_by(id: subdistrict_id)
  def status_label = STATUSES.fetch(status, status)
  def organization_type_label = UserAccessArea::ORGANIZATION_TYPES.fetch(organization_type, organization_type)
  def step_index = STEPS.index(step).to_i
  def reached?(name) = STEPS.index(name).to_i <= step_index
  def area_label
    area = subdistrict
    area ? "ต.#{area.name_th} อ.#{area.district_name_th} จ.#{area.province&.name_th}" : "-"
  end

  def masked_otp_target
    return if otp_target.blank?

    otp_channel == "sms" ? "#{otp_target.first(3)}-xxx-#{otp_target.last(4)}" : otp_target.sub(/\A(.{2}).*(@.*)\z/, '\1•••\2')
  end

  # --- Availability rules shared by the wizard's live checks and its final validation ---

  # Already managed by an existing account, or another applicant is already waiting for review.
  def self.area_status(subdistrict_id, except: nil)
    return "unknown" if subdistrict_id.blank?
    return "taken" if User.where(subdistrict_id:, role: User.roles[:subdistrict_admin]).exists? ||
                      UserAccessArea.where("subdistrict_ids @> ?", [subdistrict_id.to_i].to_json).exists?
    return "pending" if pending.where(subdistrict_id: subdistrict_id.to_i).where(:id.ne => except).exists?

    "available"
  end

  def self.username_error(value, except: nil)
    value = value.to_s.strip.downcase
    return "ต้องเป็นตัวอักษรอังกฤษพิมพ์เล็ก ตัวเลข . _ - ยาว 4–32 ตัว" unless value.match?(USERNAME_FORMAT)
    return "ชื่อผู้ใช้นี้ถูกใช้แล้ว" if User.where("LOWER(username) = ?", value).exists? || pending.where(username: value, :id.ne => except).exists?

    nil
  end

  def self.email_error(value, except: nil)
    value = value.to_s.strip.downcase
    return "รูปแบบอีเมลไม่ถูกต้อง" unless value.match?(URI::MailTo::EMAIL_REGEXP) && value.match?(/@[^@\s]+\.[a-z]{2,}\z/)
    return "อีเมลนี้ถูกใช้กับบัญชีอื่นแล้ว" if User.where("LOWER(email) = ?", value).exists? || pending.where(email: value, :id.ne => except).exists?

    nil
  end

  def self.phone_error(value, except: nil)
    phone = Sms::PhoneNumber.normalize(value)
    return "ต้องเป็นเบอร์มือถือ 10 หลัก เช่น 0812345678" unless phone
    return "เบอร์นี้ถูกใช้กับบัญชีอื่นแล้ว" if User.where(phone:).exists? || pending.where(phone:, :id.ne => except).exists?

    nil
  end

  def self.password_error(password, confirmation)
    return "รหัสผ่านต้องยาวอย่างน้อย 8 ตัว และมีทั้งตัวอักษรและตัวเลข" unless password.to_s.length >= 8 && password.match?(/[A-Za-z]/) && password.match?(/\d/)
    return "ยืนยันรหัสผ่านไม่ตรงกัน" unless password == confirmation

    nil
  end
end

# Central SMS configuration (smsmkt) edited by the system admin. The six keys carried over from SmartEMS
# (sms_api_key, sms_secret_key, sms_sender, sms_msg, sms_video_msg, host_url) plus the OTP project key.
# Secrets left blank fall back to the matching environment variable.
class SmsSetting
  include Mongoid::Document
  include Mongoid::Timestamps
  include EncryptedSecrets

  TRACKING_TAG = "<TRACKING-URL>".freeze
  ENV_FALLBACKS = { "sms_api_key" => "SMS_API_KEY", "sms_secret_key" => "SMS_SECRET_KEY", "otp_project_key" => "SMS_OTP_PROJECT_KEY" }.freeze
  # Placeholders filled in before sending; <TRACKING-URL> is left for smsmkt to replace with the shortened link.
  VARIABLES = { "organization_name" => "ชื่อหน่วยงาน", "reference_code" => "เลขที่เรื่อง", "title" => "หัวข้อเรื่อง", "system_name" => "ชื่อระบบ" }.freeze
  DEFAULT_MSG = "{{organization_name}} ได้รับเรื่อง {{reference_code}} แล้ว ติดตามสถานะได้ที่ #{TRACKING_TAG}".freeze
  DEFAULT_VIDEO_MSG = "{{organization_name}} เชิญเข้าวิดีโอคอลกับเจ้าหน้าที่ เรื่อง {{reference_code}} กดลิงก์: #{TRACKING_TAG}".freeze

  field :singleton_key, type: String, default: "sms"
  field :enabled, type: Boolean, default: true
  field :sms_sender, type: String
  field :sms_msg, type: String, default: DEFAULT_MSG
  field :sms_video_msg, type: String, default: DEFAULT_VIDEO_MSG
  field :host_url, type: String
  field :video_enabled, type: Boolean, default: false
  field :video_base_url, type: String
  field :cooldown_seconds, type: Integer, default: 60
  field :updated_by, type: String

  encrypted_secret :sms_api_key, purpose: "sms-secrets"
  encrypted_secret :sms_secret_key, purpose: "sms-secrets"
  encrypted_secret :otp_project_key, purpose: "sms-secrets"

  index({ singleton_key: 1 }, unique: true)

  validates :sms_msg, presence: true
  validates :cooldown_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600 }
  validates :sms_sender, length: { maximum: 11 }, allow_blank: true
  validate :templates_must_carry_tracking_tag
  validate :urls_must_be_http
  validates :video_base_url, presence: { message: "ต้องระบุเมื่อเปิดโหมดวิดีโอคอล" }, if: :video_enabled?
  before_validation :normalize

  def self.current
    find_or_create_by!(singleton_key: "sms")
  rescue Mongo::Error, Mongoid::Errors::MongoidError
    new
  end

  def secret(name) = public_send(name).presence || ENV[ENV_FALLBACKS.fetch(name.to_s)].presence
  def secret_source(name) = public_send(name).present? ? "settings" : (ENV[ENV_FALLBACKS.fetch(name.to_s)].present? ? "env" : nil)

  def ready? = enabled? && secret("sms_api_key").present? && secret("sms_secret_key").present? && sms_sender.present?
  def video_ready? = video_enabled? && video_base_url.present? && sms_video_msg.present?

  # host_url first (as in SmartEMS), then the notification public URL, then APP_URL.
  def effective_host_url = host_url.presence || NotificationSetting.current.base_url

  def modes
    { "tracking" => "ลิงก์ติดตามสถานะเรื่อง" }.merge(video_ready? ? { "video" => "ลิงก์วิดีโอคอลกับเจ้าหน้าที่" } : {})
  end

  private

  def normalize
    %i[sms_sender sms_msg sms_video_msg host_url video_base_url].each { |key| self[key] = self[key].to_s.strip.presence }
    self.host_url = host_url&.delete_suffix("/")
    self.video_base_url = video_base_url&.delete_suffix("/")
    self.sms_msg ||= DEFAULT_MSG
  end

  # smsmkt rejects a message with a url but no <TRACKING-URL> tag (error 1003).
  def templates_must_carry_tracking_tag
    errors.add(:sms_msg, "ต้องมี #{TRACKING_TAG} ในข้อความ") if sms_msg.present? && !sms_msg.include?(TRACKING_TAG)
    errors.add(:sms_video_msg, "ต้องมี #{TRACKING_TAG} ในข้อความ") if sms_video_msg.present? && !sms_video_msg.include?(TRACKING_TAG)
  end

  def urls_must_be_http
    { host_url: host_url, video_base_url: video_base_url }.each do |key, value|
      next if value.blank?

      uri = URI.parse(value)
      errors.add(key, "ต้องขึ้นต้นด้วย https:// หรือ http://") unless %w[http https].include?(uri.scheme) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(key, "ไม่ใช่ URL ที่ถูกต้อง")
    end
  end
end

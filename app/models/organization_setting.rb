# Settings for one local organisation (อบต.), shared by every account with the same User#organization_key
# and edited by its subdistrict admins. Map fields left blank fall back to SystemSetting.
class OrganizationSetting
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_REPORT_SOURCES = [
    { "type" => "citizen", "name" => "ประชาชน" },
    { "type" => "organization", "name" => "หน่วยงาน 1" },
    { "type" => "organization", "name" => "หน่วยงาน 2" },
    { "type" => "organization", "name" => "โรงพยาบาลส่งเสริมสุขภาพตำบล" },
    { "type" => "organization", "name" => "สถานีตำรวจภูธร" }
  ].freeze

  field :organization_key, type: String
  field :organization_name, type: String
  field :executive_name, type: String
  field :address, type: String
  field :phone, type: String
  field :email, type: String
  field :website, type: String
  field :logo, type: Hash
  field :notify_new_incidents, type: Boolean, default: true
  field :notification_sound, type: Boolean, default: false
  field :notify_pending_activities, type: Boolean, default: true
  field :map_basemap, type: String
  field :map_zoom, type: Integer
  field :map_layers, type: Array
  field :public_report_enabled, type: Boolean, default: true
  field :public_report_version, type: Integer, default: 1
  field :public_report_welcome, type: String
  field :public_report_sources, type: Array, default: -> { DEFAULT_REPORT_SOURCES.map(&:dup) }
  # The อบต.'s own GISTDA Disaster API key (encrypted); blank means the system key is used.
  field :gistda_api_key_ciphertext, type: String
  field :updated_by, type: String

  index({ organization_key: 1 }, unique: true)

  validates :organization_key, presence: true
  validates :map_basemap, inclusion: { in: SystemSetting::BASEMAPS.keys }, allow_blank: true
  validates :map_zoom, numericality: { only_integer: true, greater_than_or_equal_to: 8, less_than_or_equal_to: 18, message: "ต้องอยู่ระหว่าง 8 ถึง 18" }, allow_nil: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "ไม่ใช่อีเมลที่ถูกต้อง" }, allow_blank: true
  validate :must_keep_a_citizen_source
  before_validation :normalize

  def self.for(user)
    return if user.nil? || user.organization_key.blank? || user.system_admin?

    find_or_create_by!(organization_key: user.organization_key)
  rescue Mongo::Error, Mongoid::Errors::MongoidError
    new(organization_key: user.organization_key)
  end

  def display_name(fallback = nil) = organization_name.presence || fallback

  def report_sources
    sources = Array(public_report_sources).filter_map { |source| source = source.to_h.stringify_keys; source if source["name"].present? }
    sources.presence || DEFAULT_REPORT_SOURCES
  end

  # One source per line; the first line is the citizen form, the rest are partner organisations.
  def report_sources_text = report_sources.map { |source| source["name"] }.join("\n")

  def report_sources_text=(text)
    names = text.to_s.lines.map(&:strip).compact_blank.uniq.first(20)
    self.public_report_sources = names.each_with_index.map { |name, index| { "type" => index.zero? ? "citizen" : "organization", "name" => name.truncate(80) } }
  end

  def map_defaults(system = SystemSetting.current)
    base = system.map_defaults
    base.merge(basemap: map_basemap.presence || base[:basemap], area_zoom: map_zoom,
               layers: map_layers.nil? ? base[:layers] : (Array(map_layers) & SystemSetting::MAP_LAYERS.keys))
  end

  def gistda_api_key = decrypt(gistda_api_key_ciphertext)

  def masked_gistda_api_key
    value = gistda_api_key
    value.present? ? "••••••#{value.last(4)}" : nil
  end

  # Blank input keeps the current key; clear: true removes it so the system key applies again.
  def assign_gistda_api_key(value, clear: false)
    return self.gistda_api_key_ciphertext = nil if clear
    return if value.blank?

    self.gistda_api_key_ciphertext = encryptor.encrypt_and_sign(value.to_s.strip)
  end

  private

  def encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("organization-setting-secrets", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def decrypt(ciphertext)
    ciphertext.present? ? encryptor.decrypt_and_verify(ciphertext) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def normalize
    %i[organization_name executive_name address phone email website public_report_welcome].each { |key| self[key] = self[key].to_s.strip.presence }
    self.map_basemap = map_basemap.presence
    self.map_layers = Array(map_layers).compact_blank & SystemSetting::MAP_LAYERS.keys unless map_layers.nil?
  end

  def must_keep_a_citizen_source
    errors.add(:public_report_sources, "ต้องมีอย่างน้อย 1 รายการ") if Array(public_report_sources).empty?
  end
end

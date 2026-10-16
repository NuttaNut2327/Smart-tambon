# System-wide settings edited by the system admin (one document). API keys are encrypted at rest and,
# when left blank, fall back to the matching environment variable so .env keeps working.
class SystemSetting
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_NAME = "SMART TAMBON SAFETY THAILAND".freeze
  DEFAULT_SHORT_NAME = "SMART TAMBON".freeze
  DEFAULT_GEOCODER_URL = "https://geocode.pcm-life.com".freeze
  SECRETS = { "longdo_map_key" => "LONGDO_MAP_KEY", "maptiler_key" => "MAPTILER_KEY" }.freeze
  BASEMAPS = { "street" => "แผนที่ถนน", "satellite" => "ภาพดาวเทียม" }.freeze
  MAP_LAYERS = { "water" => "สถานีวัดน้ำและฝน", "cctv" => "กล้องวงจรปิด", "activities" => "กิจกรรมในพื้นที่", "projects" => "โครงการ", "hotspots" => "จุดความร้อน (Hotspot)" }.freeze

  field :singleton_key, type: String, default: "system"
  field :system_name, type: String, default: DEFAULT_NAME
  field :system_short_name, type: String, default: DEFAULT_SHORT_NAME
  field :organization_name, type: String
  field :contact_email, type: String
  field :contact_phone, type: String
  field :footer_text, type: String
  field :login_message, type: String
  field :logo, type: Hash
  field :longdo_map_key_ciphertext, type: String
  field :maptiler_key_ciphertext, type: String
  field :geocoder_url, type: String
  field :map_basemap, type: String, default: "street"
  field :map_center_lat, type: Float, default: 13.7563
  field :map_center_lon, type: Float, default: 100.5018
  field :map_zoom, type: Integer, default: 6
  field :map_layers, type: Array, default: MAP_LAYERS.keys
  field :updated_by, type: String

  index({ singleton_key: 1 }, unique: true)

  validates :system_name, :system_short_name, presence: true
  validates :map_basemap, inclusion: { in: BASEMAPS.keys }
  validates :map_center_lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90, message: "ต้องอยู่ระหว่าง -90 ถึง 90" }
  validates :map_center_lon, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180, message: "ต้องอยู่ระหว่าง -180 ถึง 180" }
  validates :map_zoom, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 18, message: "ต้องอยู่ระหว่าง 5 ถึง 18" }
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "ไม่ใช่อีเมลที่ถูกต้อง" }, allow_blank: true
  validate :geocoder_url_must_be_http
  before_validation :normalize

  def self.current
    find_or_create_by!(singleton_key: "system")
  rescue Mongo::Error, Mongoid::Errors::MongoidError
    new
  end

  # Secret value: saved setting first, then the environment variable.
  def secret(name) = decrypt(self[:"#{name}_ciphertext"]).presence || ENV[SECRETS.fetch(name.to_s)].presence
  def secret_source(name) = decrypt(self[:"#{name}_ciphertext"]).present? ? "settings" : (ENV[SECRETS.fetch(name.to_s)].present? ? "env" : nil)

  def masked_secret(name)
    value = secret(name)
    value.present? ? "••••••#{value.last(4)}" : nil
  end

  # Blank input keeps the current value; "clear" removes it so the environment value applies again.
  def assign_secret(name, value, clear: false)
    return self[:"#{name}_ciphertext"] = nil if clear
    return if value.blank?

    self[:"#{name}_ciphertext"] = encryptor.encrypt_and_sign(value.to_s.strip)
  end

  def longdo_map_key = secret("longdo_map_key")
  def maptiler_key = secret("maptiler_key")
  def effective_geocoder_url = geocoder_url.presence || ENV["GEOCODER_URL"].presence || DEFAULT_GEOCODER_URL

  def map_defaults
    custom_view = [map_center_lat, map_center_lon, map_zoom] != [13.7563, 100.5018, 6]
    { basemap: map_basemap, layers: Array(map_layers) & MAP_LAYERS.keys, center: [map_center_lon, map_center_lat], zoom: map_zoom, custom_view:, area_zoom: nil }
  end

  private

  def normalize
    %i[system_name system_short_name organization_name contact_email contact_phone footer_text login_message geocoder_url].each { |key| self[key] = self[key].to_s.strip.presence }
    self.system_name ||= DEFAULT_NAME
    self.system_short_name ||= DEFAULT_SHORT_NAME
    self.geocoder_url = geocoder_url&.delete_suffix("/")
    self.map_layers = Array(map_layers).compact_blank & MAP_LAYERS.keys
  end

  def geocoder_url_must_be_http
    return if geocoder_url.blank?

    uri = URI.parse(geocoder_url)
    errors.add(:geocoder_url, "ต้องขึ้นต้นด้วย http:// หรือ https://") unless %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:geocoder_url, "ไม่ใช่ URL ที่ถูกต้อง")
  end

  def encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("system-setting-secrets", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def decrypt(ciphertext)
    ciphertext.present? ? encryptor.decrypt_and_verify(ciphertext) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end

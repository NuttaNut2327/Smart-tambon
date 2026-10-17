# Central messaging configuration edited by the system admin (one document): the system's LINE Official Account,
# an optional shared Telegram bot, and the Signal gateway (signal-cli-rest-api). Each อบต. then adds its own
# group IDs as NotificationChannel records. Secrets left blank fall back to the matching environment variable.
class NotificationSetting
  include Mongoid::Document
  include Mongoid::Timestamps
  include EncryptedSecrets

  ENV_FALLBACKS = {
    "line_channel_access_token" => "LINE_CHANNEL_ACCESS_TOKEN", "line_channel_secret" => "LINE_CHANNEL_SECRET",
    "telegram_bot_token" => "TELEGRAM_BOT_TOKEN"
  }.freeze

  field :singleton_key, type: String, default: "notifications"
  field :line_enabled, type: Boolean, default: true
  field :line_bot_name, type: String
  field :line_reply_group_id, type: Boolean, default: true
  field :telegram_enabled, type: Boolean, default: true
  field :signal_enabled, type: Boolean, default: false
  field :signal_api_url, type: String
  field :signal_number, type: String
  field :webhook_enabled, type: Boolean, default: true
  field :public_base_url, type: String
  field :updated_by, type: String

  encrypted_secret :line_channel_access_token, purpose: "notification-secrets"
  encrypted_secret :line_channel_secret, purpose: "notification-secrets"
  encrypted_secret :telegram_bot_token, purpose: "notification-secrets"

  index({ singleton_key: 1 }, unique: true)

  validate :urls_must_be_http
  before_validation :normalize

  def self.current
    find_or_create_by!(singleton_key: "notifications")
  rescue Mongo::Error, Mongoid::Errors::MongoidError
    new
  end

  # Saved value first, then the environment, so .env keeps working.
  def secret(name) = public_send(name).presence || ENV[ENV_FALLBACKS.fetch(name.to_s)].presence
  def secret_source(name) = public_send(name).present? ? "settings" : (ENV[ENV_FALLBACKS.fetch(name.to_s)].present? ? "env" : nil)

  def line_ready? = line_enabled? && secret("line_channel_access_token").present?
  def signal_ready? = signal_enabled? && signal_api_url.present? && signal_number.present?
  def kind_available?(kind)
    { "line" => line_enabled?, "telegram" => telegram_enabled?, "signal" => signal_enabled?, "webhook" => webhook_enabled?,
      "facebook" => true, "instagram" => true, "pa_mqtt" => ENV["MQTT_URL"].present? }.fetch(kind.to_s, false)
  end

  def base_url = public_base_url.presence || ENV["APP_URL"].presence

  private

  def normalize
    %i[line_bot_name signal_api_url signal_number public_base_url].each { |key| self[key] = self[key].to_s.strip.presence }
    self.signal_api_url = signal_api_url&.delete_suffix("/")
    self.public_base_url = public_base_url&.delete_suffix("/")
  end

  def urls_must_be_http
    { signal_api_url: signal_api_url, public_base_url: public_base_url }.each do |key, value|
      next if value.blank?

      uri = URI.parse(value)
      errors.add(key, "ต้องขึ้นต้นด้วย http:// หรือ https://") unless %w[http https].include?(uri.scheme) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(key, "ไม่ใช่ URL ที่ถูกต้อง")
    end
  end
end

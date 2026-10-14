# An LLM the system admin makes available to the AI assistant. Several can be configured; users pick one per
# chat and the default is preselected. API keys are encrypted at rest and never sent back to the browser.
class AiProvider
  include Mongoid::Document
  include Mongoid::Timestamps

  API_FORMATS = {
    "anthropic" => "Claude (Anthropic API)",
    "openai" => "OpenAI-compatible (OpenAI, Ollama, vLLM, LM Studio, Typhoon, OpenRouter)"
  }.freeze
  EFFORTS = %w[low medium high xhigh max].freeze
  DEFAULT_MODELS = { "anthropic" => "claude-opus-5-5", "openai" => "gpt-4o-mini" }.freeze

  field :name, type: String
  field :api_format, type: String, default: "anthropic"
  field :base_url, type: String
  field :model, type: String
  field :api_key_ciphertext, type: String
  field :effort, type: String, default: "medium"
  field :max_tokens, type: Integer, default: 16_000
  field :enabled, type: Boolean, default: true
  field :is_default, type: Boolean, default: false
  field :position, type: Integer, default: 0
  field :updated_by, type: String

  validates :name, :model, presence: true
  validates :api_format, inclusion: { in: API_FORMATS.keys }
  validates :effort, inclusion: { in: EFFORTS }, allow_blank: true
  validates :max_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 1024, less_than_or_equal_to: 128_000 }
  validates :base_url, presence: { message: "ต้องระบุสำหรับผู้ให้บริการแบบ OpenAI-compatible" }, if: -> { api_format == "openai" }
  validate :base_url_must_be_http
  before_validation :normalize
  after_save :clear_other_defaults, if: :is_default?

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order_by(is_default: :desc, position: :asc, name: :asc) }

  def self.default_for_chat = enabled.ordered.first

  def anthropic? = api_format == "anthropic"
  def api_key = decrypt(api_key_ciphertext)
  def api_key? = api_key_ciphertext.present?
  def masked_api_key = api_key.present? ? "••••••#{api_key.last(4)}" : nil
  def label = "#{name} · #{model}"

  # Blank input keeps the stored key; clear: true removes it.
  def assign_api_key(value, clear: false)
    return self.api_key_ciphertext = nil if clear
    return if value.blank?

    self.api_key_ciphertext = encryptor.encrypt_and_sign(value.to_s.strip)
  end

  def as_option_json = { id: id.to_s, name: name, model: model, api_format: api_format, default: is_default? }

  private

  def normalize
    %i[name base_url model].each { |key| self[key] = self[key].to_s.strip.presence }
    self.base_url = base_url&.delete_suffix("/")
    self.model ||= DEFAULT_MODELS[api_format]
    self.effort = nil unless anthropic?
  end

  def clear_other_defaults
    self.class.where(:id.ne => id, is_default: true).update_all(is_default: false)
  end

  def base_url_must_be_http
    return if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, "ต้องขึ้นต้นด้วย http:// หรือ https://") unless %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "ไม่ใช่ URL ที่ถูกต้อง")
  end

  def encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("ai-provider-secrets", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def decrypt(ciphertext)
    ciphertext.present? ? encryptor.decrypt_and_verify(ciphertext) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end

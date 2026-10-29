# A text-to-speech service for news broadcasts (เสียงตามสาย). Central providers (organization_key nil) are set up by
# the system admin for every อบต.; an อบต. admin can add its own (e.g. its own ElevenLabs account), which only that
# อบต. sees and which wins over the central default. Each broadcast program picks one (or uses the default).
# Keys are encrypted at rest.
class TtsProvider
  include Mongoid::Document
  include Mongoid::Timestamps
  include EncryptedSecrets

  KINDS = {
    "google" => {
      label: "Google Cloud Text-to-Speech", base_url: "https://texttospeech.googleapis.com",
      voices: { "th-TH-Chirp3-HD-Achernar" => "Chirp3 HD · หญิง (Achernar)", "th-TH-Chirp3-HD-Aoede" => "Chirp3 HD · หญิง (Aoede)",
                "th-TH-Chirp3-HD-Charon" => "Chirp3 HD · ชาย (Charon)", "th-TH-Chirp3-HD-Puck" => "Chirp3 HD · ชาย (Puck)",
                "th-TH-Neural2-C" => "Neural2 · หญิง", "th-TH-Standard-A" => "Standard · หญิง" },
      key_hint: "API key ที่ขึ้นต้นด้วย AIza หรือวางเนื้อหาไฟล์ service account JSON ทั้งไฟล์ (โปรเจกต์ต้องเปิด Cloud Text-to-Speech API)"
    },
    "botnoi" => {
      label: "Botnoi Voice", base_url: "https://api-voice.botnoi.ai",
      voices: { "1" => "เสียง 1 (หญิง)", "2" => "เสียง 2 (ชาย)", "8" => "เสียง 8 (หญิง)", "9" => "เสียง 9 (ชาย)" },
      key_hint: "Botnoi-Token จาก voice.botnoi.ai — หมายเลขเสียงดูได้จากหน้าเลือกผู้พากย์ของ Botnoi"
    },
    "openai" => {
      label: "OpenAI Text-to-Speech", base_url: "https://api.openai.com",
      voices: { "alloy" => "alloy", "nova" => "nova", "shimmer" => "shimmer", "onyx" => "onyx", "echo" => "echo", "sage" => "sage" },
      key_hint: "OpenAI API key (หรือบริการที่รองรับ /v1/audio/speech)"
    },
    "elevenlabs" => {
      label: "ElevenLabs", base_url: "https://api.elevenlabs.io",
      voices: { "21m00Tcm4TlvDq8ikWAM" => "Rachel (หญิง)", "EXAVITQu4vr4xnSDxMaL" => "Sarah (หญิง)",
                "JBFqnCBsd6RMkjVDRZzb" => "George (ชาย)", "nPczCjzI2devNBz1zQrb" => "Brian (ชาย)" },
      models: { "eleven_v3" => "Eleven v3 · รองรับภาษาไทย (แนะนำ)", "eleven_v4" => "Eleven v4 · รองรับภาษาไทย",
                "eleven_v4_turbo" => "Eleven v4 Turbo · รองรับภาษาไทย เร็วกว่า" },
      key_hint: "API key จาก elevenlabs.io › Developers › API keys (ต้องมีสิทธิ์ Text to Speech และ Voices: read) — " \
                "Voice ID ดูได้จาก Voice Library หรือกด “โหลดเสียงจากบัญชี” หลังบันทึก key · ภาษาไทยต้องใช้โมเดล eleven_v3 หรือ eleven_v4"
    }
  }.freeze
  DEFAULT_MODELS = { "openai" => "gpt-4o-mini-tts", "elevenlabs" => "eleven_v3" }.freeze
  # ElevenLabs models that read Thai; multilingual_v2 and flash models don't list Thai and mispronounce it.
  THAI_MODELS = { "elevenlabs" => %w[eleven_v3 eleven_v4 eleven_v4_turbo eleven_v3_conversational] }.freeze

  field :organization_key, type: String
  field :name, type: String
  field :kind, type: String, default: "google"
  field :base_url, type: String
  field :model, type: String
  field :voice, type: String
  field :speaking_rate, type: Float, default: 1.0
  field :enabled, type: Boolean, default: true
  field :is_default, type: Boolean, default: false
  field :updated_by, type: String

  encrypted_secret :api_key, purpose: "tts-provider-secrets"

  index({ organization_key: 1, enabled: 1 })

  validates :name, :voice, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :speaking_rate, numericality: { greater_than_or_equal_to: 0.5, less_than_or_equal_to: 2.0, message: "ต้องอยู่ระหว่าง 0.5 ถึง 2.0" }
  validate :base_url_must_be_http
  validate :model_must_read_thai
  before_validation :normalize
  after_save :clear_other_defaults, if: :is_default?

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order_by(is_default: :desc, name: :asc) }
  scope :central, -> { where(organization_key: nil) }
  scope :for_organization, ->(key) { where(organization_key: key) }
  # What an อบต. may pick: the central providers plus its own.
  scope :available_to, ->(key) { key.present? ? any_of({ organization_key: nil }, { organization_key: key }) : central }

  def self.default = central.enabled.ordered.first
  # The อบต.'s own provider first (its default, else its first enabled one), then the central default.
  def self.default_for(key) = (key.present? && for_organization(key).enabled.ordered.first) || default

  def organization? = organization_key.present?

  def kind_label = KINDS.dig(kind, :label) || kind
  def voices = KINDS.dig(kind, :voices) || {}
  def models = KINDS.dig(kind, :models) || {}
  def voice_label = voices[voice] || voice
  def effective_base_url = (base_url.presence || KINDS.dig(kind, :base_url)).to_s.delete_suffix("/")
  def label = "#{name} · #{voice_label}"

  private

  def normalize
    %i[name base_url model voice].each { |key| self[key] = self[key].to_s.strip.presence }
    self.model ||= DEFAULT_MODELS[kind]
    self.voice ||= voices.keys.first
  end

  def clear_other_defaults
    self.class.where(:id.ne => id, is_default: true, organization_key:).update_all(is_default: false)
  end

  def model_must_read_thai
    allowed = THAI_MODELS[kind]
    return if allowed.nil? || model.blank? || allowed.include?(model)

    errors.add(:model, "#{model} ไม่รองรับภาษาไทย — ใช้ #{allowed.first(2).join(' หรือ ')}")
  end

  def base_url_must_be_http
    return if base_url.blank?

    uri = URI.parse(base_url)
    errors.add(:base_url, "ต้องขึ้นต้นด้วย http:// หรือ https://") unless %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:base_url, "ไม่ใช่ URL ที่ถูกต้อง")
  end
end

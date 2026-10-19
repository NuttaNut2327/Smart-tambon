# One news broadcast (ข่าวประชาสัมพันธ์/เสียงตามสาย): the LLM's bullets and announcer script, the voice file,
# an optional news image and the per-channel delivery log. Generated on a schedule or on demand, editable before
# publishing. Long work (LLM, TTS, publishing) is queued here and done by the broadcast worker.
class Broadcast
  include Mongoid::Document
  include Mongoid::Timestamps

  STATUSES = {
    "queued" => "รอสร้างข่าว",
    "generating" => "กำลังสรุปข่าว",
    "draft" => "ร่าง รอตรวจ",
    "failed" => "สร้างไม่สำเร็จ",
    "publishing" => "กำลังเผยแพร่",
    "published" => "เผยแพร่แล้ว"
  }.freeze
  # Work the worker picks up: generate the text, synthesize the voice, publish to channels.
  TASKS = %w[generate synthesize publish].freeze

  belongs_to :broadcast_program, optional: true

  field :organization_key, type: String
  field :subdistrict_id, type: Integer
  field :title, type: String
  field :bullets, type: Array, default: []
  field :script, type: String
  field :status, type: String, default: "queued"
  field :trigger, type: String, default: "manual"
  field :slot_key, type: String
  field :pending_tasks, type: Array, default: []
  field :auto_publish, type: Boolean, default: false
  field :prompt_used, type: String
  field :context_snapshot, type: Hash, default: {}
  field :ai_model, type: String
  field :audio, type: Hash
  field :audio_text_digest, type: String
  field :image, type: Hash
  field :channel_ids, type: Array, default: []
  field :deliveries, type: Array, default: []
  field :error_message, type: String
  field :generated_at, type: Time
  field :published_at, type: Time
  field :created_by, type: String
  field :updated_by, type: String

  index({ organization_key: 1, created_at: -1 })
  # Only scheduled runs carry a slot_key; manual runs store slot_key: null, which a sparse index would still
  # treat as a duplicate, so the uniqueness applies to string keys only.
  index({ broadcast_program_id: 1, slot_key: 1 },
        { unique: true, name: "broadcast_program_slot_unique", partial_filter_expression: { slot_key: { "$type" => "string" } } })
  index({ pending_tasks: 1 })

  validates :organization_key, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  before_validation :normalize

  scope :for_organization, ->(key) { where(organization_key: key) }

  def status_label = STATUSES.fetch(status, status)
  def program_name = broadcast_program&.name || "ข่าวประกาศ"
  def bullets_text = Array(bullets).join("\n")
  def bullets_text=(text)
    self.bullets = text.to_s.lines.map { |line| line.strip.sub(/\A[-•*·\d.)\s]+/, "").strip }.compact_blank.first(20)
  end
  def channels = NotificationChannel.for_organization(organization_key).where(:_id.in => Array(channel_ids)).to_a
  def busy? = pending_tasks.any? || %w[queued generating publishing].include?(status)

  # The text read aloud: the script, or the bullets when there is no script.
  def spoken_text = script.presence || bullets.join("\n")
  def audio_current? = audio.present? && audio_text_digest == Digest::SHA256.hexdigest(spoken_text.to_s)

  # Text for chat and social channels: title, bullets, then the full script.
  def post_text
    [title, bullets.map { |line| "• #{line}" }.join("\n").presence, script].compact_blank.join("\n\n")
  end

  def enqueue!(*tasks)
    add_to_set(pending_tasks: tasks.flatten.map(&:to_s) & TASKS)
  end

  def log_delivery!(channel, status:, error: nil, reference: nil)
    entry = { "channel_id" => channel.id.to_s, "channel_name" => channel.name, "kind" => channel.kind, "status" => status,
              "error" => error, "reference" => reference, "at" => Time.current.utc.iso8601 }.compact
    push(deliveries: entry)
  end

  private

  def normalize
    self.title = title.to_s.strip.presence
    self.script = script.to_s.strip.presence
    self.bullets = Array(bullets).map { |line| line.to_s.strip }.compact_blank
    self.channel_ids = Array(channel_ids).compact_blank.filter_map { |id| BSON::ObjectId.from_string(id.to_s) rescue nil }.uniq
  end
end

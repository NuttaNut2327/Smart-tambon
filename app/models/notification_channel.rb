# A group chat (or webhook) one อบต. sends notifications to. LINE and Signal go out through the central
# accounts in NotificationSetting; Telegram can use the อบต.'s own bot token or the shared one.
class NotificationChannel
  include Mongoid::Document
  include Mongoid::Timestamps
  include EncryptedSecrets

  KINDS = {
    "line" => { label: "LINE OA (กลุ่ม)", icon: "chat", target: "LINE Group ID", hint: "ขึ้นต้นด้วย C… — เชิญบัญชี LINE OA ของระบบเข้ากลุ่ม แล้วบอทจะตอบ Group ID ให้ในกลุ่ม (หรือพิมพ์ “groupid” ในกลุ่ม)" },
    "telegram" => { label: "Telegram", icon: "send", target: "Chat ID", hint: "Chat ID ของกลุ่มมักเป็นตัวเลขติดลบ เช่น -1001234567890 — เพิ่มบอทเข้ากลุ่ม ส่งข้อความในกลุ่ม แล้วกด “ค้นหา Chat ID”" },
    "signal" => { label: "Signal", icon: "forum", target: "Group ID หรือเบอร์ผู้รับ", hint: "Group ID จาก signal-cli (ขึ้นต้นด้วย group.) หรือเบอร์โทรรูปแบบ +66…" },
    "webhook" => { label: "Webhook (ระบบอื่น)", icon: "webhook", target: "Webhook URL", hint: "ระบบจะ POST JSON {event, text, data} ไปยัง URL นี้ และลงลายมือชื่อด้วย Secret ในหัว X-SmartTambon-Signature" }
  }.freeze
  TAGS = {
    "incident.created" => "เหตุการณ์ทั่วไปใหม่",
    "disaster.created" => "ภัยพิบัติใหม่",
    "activity.created" => "กิจกรรมใหม่",
    "announcement" => "ประกาศ/ข้อความทั่วไป"
  }.freeze

  field :organization_key, type: String
  field :name, type: String
  field :kind, type: String, default: "line"
  field :target, type: String
  field :tags, type: Array, default: -> { %w[incident.created disaster.created] }
  field :enabled, type: Boolean, default: true
  field :last_sent_at, type: Time
  field :last_error, type: String
  field :created_by, type: String
  field :updated_by, type: String

  # Telegram: the อบต.'s own bot token (optional). Webhook: the signing secret (optional).
  encrypted_secret :token, purpose: "notification-secrets"

  index({ organization_key: 1, kind: 1 })

  validates :organization_key, :name, :target, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validate :target_must_match_kind
  validate :tags_must_be_known
  before_validation :normalize

  scope :for_organization, ->(key) { where(organization_key: key) }
  scope :enabled, -> { where(enabled: true) }

  def kind_label = KINDS.dig(kind, :label) || kind
  def kind_icon = KINDS.dig(kind, :icon) || "notifications"
  def tag_labels = tags.map { |tag| TAGS.fetch(tag, tag) }
  def subscribed?(tag) = tags.include?(tag.to_s)

  def masked_target
    return target if kind == "webhook" || target.to_s.length <= 10

    "#{target.first(6)}…#{target.last(4)}"
  end

  private

  def normalize
    %i[name target].each { |key| self[key] = self[key].to_s.strip.presence }
    self.tags = Array(tags).compact_blank.uniq
  end

  def target_must_match_kind
    return if target.blank?

    case kind
    when "line"
      errors.add(:target, "LINE Group ID ต้องขึ้นต้นด้วย C (กลุ่ม), R (ห้อง) หรือ U (ผู้ใช้) ตามด้วยอักขระ 32 ตัว") unless target.match?(/\A[CRU][0-9a-f]{32}\z/)
    when "telegram"
      errors.add(:target, "Chat ID ต้องเป็นตัวเลข (กลุ่มมักติดลบ) หรือ @ชื่อช่อง") unless target.match?(/\A(-?\d+|@[A-Za-z0-9_]{5,})\z/)
    when "signal"
      errors.add(:target, "ต้องเป็น Group ID (group.…) หรือเบอร์รูปแบบ +66…") unless target.match?(/\A(group\.[A-Za-z0-9+\/=_-]+|\+\d{8,15})\z/)
    when "webhook"
      begin
        uri = URI.parse(target)
        errors.add(:target, "ต้องเป็น URL ที่ขึ้นต้นด้วย https:// หรือ http://") unless %w[http https].include?(uri.scheme) && uri.host.present?
      rescue URI::InvalidURIError
        errors.add(:target, "ไม่ใช่ URL ที่ถูกต้อง")
      end
    end
  end

  def tags_must_be_known
    unknown = tags - TAGS.keys
    errors.add(:tags, "ไม่รู้จัก #{unknown.join(', ')}") if unknown.any?
  end
end

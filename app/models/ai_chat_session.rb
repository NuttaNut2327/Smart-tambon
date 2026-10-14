# One AI assistant conversation, private to the user who started it. Data the assistant reads is always scoped
# to that user's organisation (อบต.) through the same visible_to rules the rest of the app uses.
class AiChatSession
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_TITLE = "แชตใหม่".freeze
  MAX_TURNS = 40

  field :user_id, type: Integer
  field :organization_key, type: String
  field :title, type: String, default: DEFAULT_TITLE
  field :ai_provider_id, type: BSON::ObjectId
  field :message_count, type: Integer, default: 0

  has_many :messages, class_name: "AiChatMessage", inverse_of: :session, dependent: :delete_all

  index({ user_id: 1, updated_at: -1 })

  validates :user_id, presence: true

  scope :owned_by, ->(user) { where(user_id: user.id) }

  def provider = (ai_provider_id && AiProvider.enabled.where(id: ai_provider_id).first) || AiProvider.default_for_chat
  def default_title? = title.blank? || title == DEFAULT_TITLE
  def full? = messages.where(role: "user").count >= MAX_TURNS

  def as_list_json
    { id: id.to_s, title: title, message_count: message_count, ai_provider_id: ai_provider_id&.to_s, updated_at: updated_at }
  end

  def as_detail_json
    as_list_json.merge(messages: messages.asc(:seq).map(&:as_chat_json), full: full?)
  end
end

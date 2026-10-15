# A LINE group or room the system's Official Account has joined, recorded from the LINE webhook so the
# system admin can see where the bot is. The bot also replies with the group ID inside the group, which is how
# อบต. staff get the ID to paste into their NotificationChannel.
class LineGroup
  include Mongoid::Document
  include Mongoid::Timestamps

  field :group_id, type: String
  field :source_type, type: String, default: "group"
  field :group_name, type: String
  field :picture_url, type: String
  field :joined_at, type: Time
  field :left_at, type: Time
  field :last_event_at, type: Time

  index({ group_id: 1 }, unique: true)

  validates :group_id, presence: true

  scope :active, -> { where(left_at: nil) }

  def active? = left_at.nil?
end

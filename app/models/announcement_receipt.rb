# One per user per announcement. `acknowledged_at` is set when the user presses
# "รับทราบ"; corner announcements (no button) only record `first_seen_at`.
class AnnouncementReceipt
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :announcement
  field :user_id, type: Integer
  field :first_seen_at, type: Time
  field :acknowledged_at, type: Time

  index({ announcement_id: 1, user_id: 1 }, { unique: true })
  index({ user_id: 1 })

  validates :user_id, presence: true

  def self.for(announcement, user)
    find_or_create_by(announcement_id: announcement.id, user_id: user.id) do |receipt|
      receipt.first_seen_at = Time.current
    end
  rescue Mongo::Error::OperationFailure
    find_by(announcement_id: announcement.id, user_id: user.id)
  end
end

class CitizenIncidentFollower
  include Mongoid::Document
  include Mongoid::Timestamps

  field :incident_id, type: BSON::ObjectId
  field :line_user_id, type: String
  field :line_display_name, type: String
  field :notified_events, type: Array, default: []

  index({ incident_id: 1, line_user_id: 1 }, unique: true)

  validates :incident_id, :line_user_id, presence: true
end

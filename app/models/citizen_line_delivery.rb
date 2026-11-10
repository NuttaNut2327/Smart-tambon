class CitizenLineDelivery
  include Mongoid::Document
  include Mongoid::Timestamps

  EVENTS = %w[submitted acknowledged completed].freeze

  field :incident_id, type: BSON::ObjectId
  field :event, type: String
  field :line_user_id, type: String
  field :status, type: String, default: "pending"
  field :message, type: String
  field :error_message, type: String
  field :sent_at, type: Time
  field :attempts, type: Integer, default: 0

  index({ incident_id: 1, event: 1 }, unique: true)
  validates :incident_id, :event, :line_user_id, presence: true
  validates :event, inclusion: { in: EVENTS }
end

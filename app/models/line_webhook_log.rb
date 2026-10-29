# A short-lived audit trail of requests received from LINE Messaging API. Payloads are retained for 30 days
# so system administrators can diagnose group registration and delivery issues without growing MongoDB forever.
class LineWebhookLog
  include Mongoid::Document
  include Mongoid::Timestamps

  RETENTION_PERIOD = 30.days

  field :received_at, type: Time
  field :status, type: String
  field :signature_valid, type: Boolean, default: false
  field :event_types, type: Array, default: []
  field :group_ids, type: Array, default: []
  field :destination, type: String
  field :payload, type: Hash, default: {}
  field :body_size, type: Integer, default: 0
  field :request_id, type: String
  field :error_message, type: String

  index({ received_at: 1 }, expire_after_seconds: RETENTION_PERIOD.to_i)
  index({ group_ids: 1 })
  index({ event_types: 1 })

  validates :received_at, :status, presence: true

  scope :newest_first, -> { order_by(received_at: :desc) }
end

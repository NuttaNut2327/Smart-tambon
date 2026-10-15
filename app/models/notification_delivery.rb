# One send attempt to one channel, kept for the test page and troubleshooting.
class NotificationDelivery
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  field :organization_key, type: String
  field :channel_id, type: BSON::ObjectId
  field :channel_name, type: String
  field :kind, type: String
  field :tag, type: String
  field :source, type: String, default: "event"
  field :incident_id, type: BSON::ObjectId
  field :status, type: String
  field :error, type: String
  field :text, type: String
  field :sent_by, type: String

  index({ organization_key: 1, created_at: -1 })
  index({ created_at: 1 }, { expire_after_seconds: 90.days.to_i })

  scope :for_organization, ->(key) { where(organization_key: key) }

  def sent? = status == "sent"
  def source_label = { "event" => "อัตโนมัติ", "test" => "ทดสอบ", "simulation" => "จำลองเหตุใหม่" }.fetch(source, source)
end

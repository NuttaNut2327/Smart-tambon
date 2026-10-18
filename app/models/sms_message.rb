# Audit record of every SMS/OTP request sent to smsmkt: what was sent, to whom, by whom, and what the provider said.
class SmsMessage
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  field :kind, type: String, default: "link"
  field :incident_id, type: BSON::ObjectId
  field :organization_key, type: String
  field :mode, type: String
  field :phone, type: String
  field :message, type: String
  field :link, type: String
  field :sender, type: String
  field :status, type: String
  field :http_status, type: String
  field :provider_code, type: String
  field :provider_response, type: Hash, default: {}
  field :error, type: String
  field :sent_by, type: String

  index({ incident_id: 1, created_at: -1 })
  index({ created_at: -1 })

  def sent? = status == "SENT"
  def masked_phone = phone.to_s.length >= 10 ? "#{phone.first(3)}-xxx-#{phone.last(4)}" : phone
end

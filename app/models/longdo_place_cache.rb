class LongdoPlaceCache
  include Mongoid::Document
  include Mongoid::Timestamps

  field :query_key, type: String
  field :category, type: String
  field :longdo_tag, type: String
  field :center, type: Array
  field :span, type: String
  field :area, type: String
  field :places, type: Array, default: []
  field :response_meta, type: Hash, default: {}
  field :expires_at, type: Time

  index({ query_key: 1 }, unique: true)
  index({ expires_at: 1 }, expire_after_seconds: 0)

  validates :query_key, :category, :span, :expires_at, presence: true

  def fresh?
    expires_at.future?
  end
end

class DynamicLayer
  include Mongoid::Document
  include Mongoid::Timestamps
  field :layer_key, type: String
  field :name, type: String
  field :payload, type: Hash, default: {}
  field :location, type: Array
  field :subdistrict_id, type: Integer
  field :owner_user_id, type: Integer
  field :shared_with_all, type: Boolean, default: false
  field :active, type: Boolean, default: true
  index({ layer_key: 1 })
  index({ location: "2dsphere" })
  index({ subdistrict_id: 1 })
  index({ owner_user_id: 1 })
  index({ shared_with_all: 1 })
  validates :layer_key, :name, presence: true
end

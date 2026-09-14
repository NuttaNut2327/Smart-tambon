class BoundaryGeojsonCache
  include Mongoid::Document
  include Mongoid::Timestamps

  field :key, type: String
  field :source_version, type: String
  field :payload, type: Hash, default: {}
  field :expires_at, type: Time

  index({ key: 1 }, unique: true)
  index({ expires_at: 1 }, expire_after_seconds: 0)

  def fresh_for?(version)
    source_version == version.to_s && expires_at&.future?
  end
end

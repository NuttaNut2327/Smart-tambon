class LongdoUsageStat
  include Mongoid::Document
  include Mongoid::Timestamps

  field :stat_key, type: String
  field :longdo_requests, type: Integer, default: 0
  field :cache_hits, type: Integer, default: 0
  field :cache_misses, type: Integer, default: 0
  field :failed_requests, type: Integer, default: 0

  index({ stat_key: 1 }, unique: true)
  validates :stat_key, presence: true
end

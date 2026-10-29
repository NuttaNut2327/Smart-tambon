class LocationTrackerReading
  include Mongoid::Document
  include Mongoid::Timestamps

  field :imported_dataset_id, type: BSON::ObjectId
  field :sensor_id, type: String
  # Position reported by the device itself (EPSG:4326); unlike fixed sensors it changes with every reading.
  field :latitude, type: Float
  field :longitude, type: Float
  field :speed_kmh, type: Float
  field :heading_deg, type: Float
  field :accuracy_m, type: Float
  field :altitude_m, type: Float
  field :observed_at, type: Time
  field :source, type: String, default: "http"
  field :metadata, type: Hash, default: {}

  index({ imported_dataset_id: 1, sensor_id: 1, observed_at: -1 })
  index({ sensor_id: 1, observed_at: -1 })
  validates :imported_dataset_id, :sensor_id, :latitude, :longitude, :observed_at, presence: true
  validates :source, inclusion: { in: %w[http mqtt] }

  def as_reading_json
    { sensor_id:, latitude:, longitude:, speed_kmh:, heading_deg:, accuracy_m:, altitude_m:,
      observed_at: observed_at&.iso8601, source:, metadata: }
  end
end

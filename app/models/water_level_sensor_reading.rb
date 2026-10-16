class WaterLevelSensorReading
  include Mongoid::Document
  include Mongoid::Timestamps

  field :imported_dataset_id, type: BSON::ObjectId
  field :sensor_id, type: String
  # Water level in metres, as reported by the sensor (relative to its own datum unless the device says otherwise).
  field :water_level_m, type: Float
  field :rainfall_mm, type: Float
  field :observed_at, type: Time
  field :latitude, type: Float
  field :longitude, type: Float
  field :source, type: String, default: "http"
  field :metadata, type: Hash, default: {}

  index({ imported_dataset_id: 1, sensor_id: 1, observed_at: -1 })
  index({ sensor_id: 1, observed_at: -1 })
  validates :imported_dataset_id, :sensor_id, :water_level_m, :observed_at, presence: true
  validates :source, inclusion: { in: %w[http mqtt] }

  def as_reading_json
    { sensor_id:, water_level_m:, rainfall_mm:, observed_at: observed_at&.iso8601, source:, metadata: }
  end
end

class Pm25SensorReading
  include Mongoid::Document
  include Mongoid::Timestamps

  field :imported_dataset_id, type: BSON::ObjectId
  field :sensor_id, type: String
  field :pm25, type: Float
  field :pm25_avg_24h, type: Float
  field :pm10, type: Float
  field :temperature_c, type: Float
  field :humidity_percent, type: Float
  field :observed_at, type: Time
  field :latitude, type: Float
  field :longitude, type: Float
  field :source, type: String, default: "http"
  field :metadata, type: Hash, default: {}

  index({ imported_dataset_id: 1, sensor_id: 1, observed_at: -1 })
  index({ sensor_id: 1, observed_at: -1 })
  validates :imported_dataset_id, :sensor_id, :pm25, :observed_at, presence: true
  validates :source, inclusion: { in: %w[http mqtt] }

  def as_reading_json
    { sensor_id:, pm25:, pm25_avg_24h:, pm10:, temperature_c:, humidity_percent:, observed_at: observed_at&.iso8601, source:, metadata: }
  end
end

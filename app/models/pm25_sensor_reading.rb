class Pm25SensorReading
  include Mongoid::Document
  include Mongoid::Timestamps

  field :imported_dataset_id, type: BSON::ObjectId
  field :sensor_id, type: String
  field :pm25, type: Float
  field :pm25_avg_24h, type: Float
  field :observed_at, type: Time
  field :latitude, type: Float
  field :longitude, type: Float

  index({ imported_dataset_id: 1, sensor_id: 1, observed_at: -1 })
  validates :imported_dataset_id, :sensor_id, :pm25, :observed_at, presence: true
end

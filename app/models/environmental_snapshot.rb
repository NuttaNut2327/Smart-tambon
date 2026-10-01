class EnvironmentalSnapshot
  include Mongoid::Document
  include Mongoid::Timestamps

  field :subdistrict_code, type: String
  field :subdistrict_name, type: String
  field :pm25, type: Float
  field :pm25_avg_24h, type: Float
  field :temperature_c, type: Float
  field :temperature_source, type: String
  field :temperature_source_label, type: String
  field :temperature_observed_at, type: Time
  field :temperature_station_id, type: String
  field :temperature_station_name, type: String
  field :temperature_station_agency, type: String
  field :rain_24h_mm, type: Float
  field :pm25_observed_at, type: Time
  field :thaiwater_pm25, type: Float
  field :thaiwater_pm25_avg_24h, type: Float
  field :thaiwater_pm25_observed_at, type: Time
  field :thaiwater_station_id, type: String
  field :thaiwater_station_name, type: String
  field :thaiwater_station_agency, type: String
  field :weather_observed_at, type: Time
  field :expires_at, type: Time

  index({ subdistrict_code: 1 }, unique: true)
  index({ expires_at: 1 })

  validates :subdistrict_code, presence: true, uniqueness: true

  def fresh?
    expires_at&.future?
  end
end

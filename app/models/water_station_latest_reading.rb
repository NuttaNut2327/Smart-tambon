class WaterStationLatestReading < ApplicationRecord
  belongs_to :water_station

  validates :water_station_id, uniqueness: true
end

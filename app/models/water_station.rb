class WaterStation < ApplicationRecord
  validates :station_id, :location, presence: true

  scope :inside, ->(boundary) { where("ST_Intersects(water_stations.location, ?)", boundary) }

  def as_map_json
    {
      id: station_id,
      code: station_code,
      name: station_name_th.presence || station_name_en.presence || station_code,
      lon: location.x,
      lat: location.y,
      water_level_m_msl: water_level_m_msl,
      water_level_observed_at: water_level_observed_at,
      rainfall_value: rainfall_value,
      rainfall_observed_at: rainfall_observed_at,
      flow_rate_m3_s: flow_rate_m3_s,
      river_capacity_percent: river_capacity_percent,
      equipment: equipment
    }
  end
end

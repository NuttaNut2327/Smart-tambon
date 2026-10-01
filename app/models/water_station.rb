class WaterStation < ApplicationRecord
  has_one :latest_reading, class_name: "WaterStationLatestReading", dependent: :destroy, inverse_of: :water_station
  delegate :water_level_m_msl, :water_level_observed_at, :water_level_source,
    :rainfall_value, :rainfall_observed_at, :rainfall_source,
    :flow_rate_m3_s, :river_capacity_percent, :source_observed_at,
    to: :latest_reading, allow_nil: true

  validates :station_id, :location, presence: true

  scope :inside, ->(boundary) {
    where(
      "ST_Covers(ST_CollectionExtract(ST_MakeValid(ST_GeomFromText(?, 4326)), 3), water_stations.location::geometry)",
      boundary.as_text
    )
  }

  def as_map_json
    reading = latest_reading
    {
      id: station_id,
      code: station_code,
      name: station_name_th.presence || station_name_en.presence || station_code,
      lon: location.x,
      lat: location.y,
      water_level_m_msl: reading&.water_level_m_msl,
      water_level_observed_at: reading&.water_level_observed_at,
      rainfall_value: reading&.rainfall_value,
      rainfall_observed_at: reading&.rainfall_observed_at,
      flow_rate_m3_s: reading&.flow_rate_m3_s,
      river_capacity_percent: reading&.river_capacity_percent,
      equipment: equipment,
      source: source,
      source_label: source_label,
      owner: agency_name.presence || agency,
      water_level_source: reading&.water_level_source.presence || source,
      rainfall_source: reading&.rainfall_source.presence || source,
      observed_at: reading&.source_observed_at,
      data_status: data_status
    }
  end

  def source_label
    { "own" => "เซนเซอร์ของระบบ", "dwr" => "กรมทรัพยากรน้ำ (DWR)", "thaiwater" => "ThaiWater" }.fetch(source, source.to_s)
  end


  def data_status
    observed_at = latest_reading&.source_observed_at
    return "ไม่มีข้อมูล" unless observed_at
    return "ออฟไลน์" if observed_at < 24.hours.ago || sync_status == "offline"
    return "ข้อมูลล่าช้า" if observed_at < 1.hour.ago || sync_status == "disconnected"

    "ออนไลน์"
  end
end

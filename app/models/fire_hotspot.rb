class FireHotspot < ApplicationRecord
  SOURCE_LABELS = {
    "VIIRS_SNPP_NRT" => "VIIRS S-NPP",
    "VIIRS_NOAA20_NRT" => "VIIRS NOAA-20",
    "VIIRS_NOAA21_NRT" => "VIIRS NOAA-21",
    "MODIS_NRT" => "MODIS Terra/Aqua"
  }.freeze

  validates :hotspot_key, :source, :location, :acquired_at, presence: true

  scope :recent, ->(hours = 24) { where(acquired_at: hours.to_f.hours.ago..) }
  scope :inside, ->(boundary) {
    where(
      "ST_Covers(ST_CollectionExtract(ST_MakeValid(ST_GeomFromText(?, 4326)), 3), fire_hotspots.location::geometry)",
      boundary.as_text
    )
  }

  # Largest number of hotspots found inside any circle of `area_sq_km` centred on a hotspot that lies in
  # `selected_wkt` (EPSG:4326). This answers rule conditions like "at least 3 hotspots within 5 sq km".
  def self.max_cluster_count(selected_wkt:, area_sq_km:, hours: 24)
    radius_m = Math.sqrt(area_sq_km.to_f / Math::PI) * 1000
    return 0 unless radius_m.positive?

    connection.select_value(sanitize_sql_array([<<~SQL.squish, { wkt: selected_wkt, radius: radius_m, since: hours.to_f.hours.ago }]))
      WITH selected AS (SELECT ST_MakeValid(ST_GeomFromText(:wkt, 4326)) AS geom),
      candidates AS (
        SELECT fire_hotspots.id, fire_hotspots.location
        FROM fire_hotspots, selected
        WHERE fire_hotspots.acquired_at >= :since AND ST_Intersects(fire_hotspots.location::geometry, selected.geom)
      )
      SELECT COALESCE(MAX(neighbours), 0) FROM (
        SELECT COUNT(other.id) AS neighbours
        FROM candidates centre
        JOIN fire_hotspots other ON other.acquired_at >= :since AND ST_DWithin(other.location, centre.location, :radius)
        GROUP BY centre.id
      ) counts
    SQL
      .to_i
  end

  def as_map_json
    {
      id:, lon: location.x, lat: location.y, acquired_at: acquired_at.iso8601,
      source:, source_label: SOURCE_LABELS.fetch(source, source), satellite:, instrument:,
      brightness:, frp:, confidence:, daynight:
    }
  end
end

class Subdistrict < ApplicationRecord
  belongs_to :province
  validates :name_th, :code, presence: true

  scope :alphabetical, -> { order(Arel.sql("name_th COLLATE \"th-TH-x-icu\" ASC")) }

  def as_geojson(simplified: false)
    { type: "Feature", id: id,
      properties: { name_th:, name_en:, code:, level: "subdistrict", province_id:,
                    district_code:, district_name_th:, district_name_en:, population:,
                    center: center && [center.x, center.y] },
      geometry: simplified ? simplified_geometry : boundary && RGeo::GeoJSON.encode(boundary) }
  end

  private

  def simplified_geometry
    return unless boundary

    sql = self.class.sanitize_sql_array([
      "SELECT ST_AsGeoJSON(ST_SimplifyPreserveTopology(boundary::geometry, ?)) FROM subdistricts WHERE id = ?", 0.0005, id
    ])
    JSON.parse(self.class.connection.select_value(sql))
  end
end

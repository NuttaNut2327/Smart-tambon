class Province < ApplicationRecord
  has_many :subdistricts, dependent: :destroy
  validates :name_th, :code, presence: true

  scope :alphabetical, -> { order(Arel.sql("name_th COLLATE \"th-TH-x-icu\" ASC")) }

  def as_geojson(simplified: false)
    { type: "Feature", id: id,
      properties: { name_th:, name_en:, code:, level: "province",
                    center: center && [center.x, center.y] },
      geometry: simplified ? simplified_geometry : boundary && RGeo::GeoJSON.encode(boundary) }
  end

  private

  def simplified_geometry
    return unless boundary

    sql = self.class.sanitize_sql_array([
      "SELECT ST_AsGeoJSON(ST_SimplifyPreserveTopology(boundary::geometry, ?)) FROM provinces WHERE id = ?", 0.003, id
    ])
    JSON.parse(self.class.connection.select_value(sql))
  end
end

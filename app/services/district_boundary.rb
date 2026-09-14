class DistrictBoundary
  def self.for_province(province, simplified: false)
    union_geometry = "ST_Multi(ST_CollectionExtract(ST_UnaryUnion(ST_Collect(boundary::geometry)), 3))"
    geometry = simplified ? "ST_SimplifyPreserveTopology(#{union_geometry}, 0.0015)" : union_geometry
    sql = <<~SQL.squish
      SELECT district_code,
             MAX(district_name_th) AS name_th,
             MAX(district_name_en) AS name_en,
             COUNT(*) AS subdistrict_count,
             ST_AsGeoJSON(#{geometry}) AS geometry_json
      FROM subdistricts
      WHERE province_id = ? AND district_code IS NOT NULL AND district_code <> '' AND boundary IS NOT NULL
      GROUP BY district_code
      ORDER BY MAX(district_name_th) COLLATE "th-TH-x-icu" ASC
    SQL

    rows = Subdistrict.connection.select_all(Subdistrict.sanitize_sql_array([ sql, province.id ]))
    rows.map { |row| as_feature(row) }
  end

  def self.find_in_province(province, district_code, simplified: false)
    for_province(province, simplified: simplified).find { |feature| feature[:id].to_s == district_code.to_s }
  end

  def self.as_feature(row)
    {
      type: "Feature",
      id: row["district_code"],
      properties: {
        level: "district",
        district_code: row["district_code"],
        name_th: row["name_th"],
        name_en: row["name_en"],
        subdistrict_count: row["subdistrict_count"].to_i
      },
      geometry: row["geometry_json"].present? ? JSON.parse(row["geometry_json"]) : nil
    }
  end
  private_class_method :as_feature
end

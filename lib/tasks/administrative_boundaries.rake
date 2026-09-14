require "json"

namespace :geo do
  desc "Import GISTDA tambon GeoJSON (FILE=tmp/data/tambons.geojson)"
  task import_tambons: :environment do
    file = ENV.fetch("FILE", Rails.root.join("tmp/data/tambons.geojson").to_s)
    abort "GeoJSON file not found: #{file}" unless File.exist?(file)

    features = JSON.parse(File.read(file)).fetch("features")
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    imported = 0
    rejected = []

    features.each_with_index do |feature, index|
      properties = feature.fetch("properties")
      province_code = properties["P_code"].to_s.rjust(2, "0")
      amphoe_code = properties["A_code"].to_s.rjust(2, "0")
      tambon_code = properties["T_code"].to_s.rjust(2, "0")
      code = properties["Admin_code"].to_s.gsub(/\D/, "")
      code = "#{province_code}#{amphoe_code}#{tambon_code}" unless code.length >= 6

      province = Province.find_or_initialize_by(code: province_code)
      province.update!(
        name_th: clean_area_name(properties["P_Name_T"], /\A(?:จังหวัด|จ\.)\s*/),
        name_en: clean_area_name(properties["P_Name_E"], /\A(?:CHANGWAT|PROVINCE)\s+/i)
      )

      decoded = RGeo::GeoJSON.decode(feature.fetch("geometry").to_json,
                                      json_parser: :json, geo_factory: factory)
      geometry = decoded.respond_to?(:geometry) ? decoded.geometry : decoded
      geometry = factory.multi_polygon([geometry]) if geometry.geometry_type == RGeo::Feature::Polygon

      item = Subdistrict.find_or_initialize_by(code: code)
      item.assign_attributes(
        province: province,
        name_th: clean_area_name(properties["T_Name_T"], /\A(?:ตำบล|แขวง)\s*/),
        name_en: clean_area_name(properties["T_Name_E"], /\A(?:TAMBON|KHWAENG)\s+/i),
        district_code: "#{province_code}#{amphoe_code}",
        district_name_th: clean_area_name(properties["A_Name_T"], /\A(?:อำเภอ|เขต)\s*/),
        district_name_en: clean_area_name(properties["A_Name_E"], /\A(?:AMPHOE|KHET)\s+/i),
        population: properties["Population"],
        source_name: properties["Source_Nam"],
        source_date: parse_arcgis_date(properties["Source_dat"]),
        boundary: geometry
      )
      item.save!
      imported += 1
      puts "Imported #{imported}/#{features.length}" if ((index + 1) % 250).zero?
    rescue StandardError => e
      rejected << { index: index, code: code, error: e.message }
    end

    # ซ่อม geometry และคำนวณจุดภายใน polygon ของตำบล
    ActiveRecord::Base.connection.execute <<~SQL
      UPDATE subdistricts
      SET boundary = ST_Multi(ST_CollectionExtract(ST_MakeValid(boundary::geometry), 3))::geography,
          center = ST_PointOnSurface(ST_MakeValid(boundary::geometry))::geography
      WHERE boundary IS NOT NULL
    SQL

    # รวม polygon ตำบลเป็นขอบเขตจังหวัด เพื่อให้ทั้งสองระดับมาจากชุดข้อมูลเดียวกัน
    ActiveRecord::Base.connection.execute <<~SQL
      UPDATE provinces p SET
        boundary = boundaries.geometry::geography,
        center = ST_PointOnSurface(boundaries.geometry)::geography
      FROM (
        SELECT province_id,
               ST_Multi(ST_CollectionExtract(ST_UnaryUnion(ST_Collect(boundary::geometry)), 3)) AS geometry
        FROM subdistricts WHERE boundary IS NOT NULL GROUP BY province_id
      ) boundaries
      WHERE p.id = boundaries.province_id
    SQL

    if rejected.any?
      report = Rails.root.join("tmp/data/rejected-tambons.json")
      File.write(report, JSON.pretty_generate(rejected))
      warn "Rejected #{rejected.length} features; see #{report}"
    end
    puts "Completed: #{imported} tambons and #{Province.where.not(boundary: nil).count} provinces"
  end

  def parse_arcgis_date(value)
    return if value.blank?
    value.to_s.match?(/\A\d+\z/) ? Time.at(value.to_i / 1000).to_date : Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  def clean_area_name(value, prefix_pattern)
    value.to_s.sub(prefix_pattern, "").strip.presence
  end
end

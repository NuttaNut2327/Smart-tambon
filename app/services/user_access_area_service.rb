class UserAccessAreaService
  def initialize(user:, name:, subdistrict_ids:, boundary_file:)
    @user = user
    @name = name.to_s.strip
    @subdistrict_ids = Array(subdistrict_ids).reject(&:blank?).map { |id| Integer(id.to_s, 10) }.uniq
    @boundary_file = boundary_file
  end

  def save!
    return @user.access_area&.destroy! if @user.system_admin?

    area = @user.access_area || @user.build_access_area
    if @boundary_file.present?
      boundary, source = uploaded_boundary
      source_label = { "kmz" => "KMZ", "kml" => "KML", "geojson" => "GeoJSON", "shapefile" => "Shapefile" }.fetch(source)
      label = @name.presence || "ขอบเขตที่กำหนดจาก #{source_label}"
      area.assign_attributes(name: label, source: source, subdistrict_ids: @subdistrict_ids, boundary: boundary)
    else
      subdistricts = Subdistrict.where(id: @subdistrict_ids).index_by(&:id)
      raise ArgumentError, "กรุณาเลือกตำบลอย่างน้อย 1 ตำบล หรืออัปโหลด KMZ" if subdistricts.empty?
      found_ids = subdistricts.keys
      missing_ids = @subdistrict_ids - found_ids
      raise ArgumentError, "ไม่พบตำบลที่เลือก: #{missing_ids.join(', ')}" if missing_ids.any?
      subdistricts = @subdistrict_ids.map { |id| subdistricts.fetch(id) }

      area.assign_attributes(name: @name.presence || subdistricts.map(&:name_th).join(", "), source: "subdistricts",
        subdistrict_ids: @subdistrict_ids, boundary: merged_boundary(subdistricts))
    end
    area.save!
    area
  end

  private

  def merged_boundary(subdistricts)
    missing_boundaries = subdistricts.select { |subdistrict| subdistrict.boundary.blank? }
    if missing_boundaries.any?
      raise ArgumentError, "ตำบลที่เลือกไม่มีข้อมูลขอบเขต: #{missing_boundaries.map(&:name_th).join(', ')}"
    end
    boundaries = subdistricts.map(&:boundary)

    factory = boundaries.first.factory
    polygons = boundaries.flat_map do |boundary|
      boundary.geometry_type.type_name == "Polygon" ? [boundary] : boundary.to_a
    end
    factory.multi_polygon(polygons)
  end

  def uploaded_boundary
    extension = File.extname(@boundary_file.original_filename).downcase
    return [kmz_boundary, "kmz"] if extension == ".kmz"
    return [kml_boundary, "kml"] if extension == ".kml"
    return [geojson_boundary, "geojson"] if %w[.geojson .json].include?(extension)
    return [shapefile_boundary, "shapefile"] if %w[.shp .zip].include?(extension)

    raise ArgumentError, "รองรับไฟล์ KMZ, KML, GeoJSON, SHP หรือ ZIP ของ Shapefile เท่านั้น"
  end

  def kmz_boundary
    require "zip"
    require "rexml/document"

    xml = Zip::File.open(@boundary_file.path) do |zip|
      entry = zip.find { |item| item.name.downcase.end_with?(".kml") }
      raise ArgumentError, "ไม่พบไฟล์ KML ภายใน KMZ" unless entry
      entry.get_input_stream.read
    end
    kml_geometry(xml, "KMZ")
  rescue Zip::Error => error
    raise ArgumentError, "อ่านไฟล์ KMZ ไม่สำเร็จ: #{error.message}"
  end

  def kml_boundary
    kml_geometry(File.read(@boundary_file.path), "KML")
  rescue Errno::ENOENT, IOError => error
    raise ArgumentError, "อ่านไฟล์ KML ไม่สำเร็จ: #{error.message}"
  end

  def kml_geometry(xml, source_label)
    document = REXML::Document.new(xml)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    polygons = document.get_elements("//Polygon//outerBoundaryIs//LinearRing//coordinates").filter_map do |node|
      points = node.text.to_s.split(/\s+/).filter_map do |coordinate|
        lon, lat = coordinate.split(",").first(2).map { |value| Float(value, exception: false) }
        factory.point(lon, lat) if lon && lat
      end
      next if points.length < 4
      points << points.first unless points.first == points.last
      factory.polygon(factory.linear_ring(points))
    end
    raise ArgumentError, "#{source_label} ต้องมีขอบเขต Polygon อย่างน้อย 1 พื้นที่" if polygons.empty?
    factory.multi_polygon(polygons)
  rescue REXML::ParseException => error
    raise ArgumentError, "อ่านไฟล์ #{source_label} ไม่สำเร็จ: #{error.message}"
  end

  def geojson_boundary
    require "rgeo/geojson"

    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    decoded = RGeo::GeoJSON.decode(File.read(@boundary_file.path), geo_factory: factory)
    raise ArgumentError, "อ่านไฟล์ GeoJSON ไม่สำเร็จ" unless decoded

    geometries = if decoded.respond_to?(:features)
      decoded.features.map(&:geometry)
    elsif decoded.respond_to?(:geometry)
      [decoded.geometry]
    else
      [decoded]
    end
    polygons = geometries.flat_map { |geometry| polygon_parts(geometry) }
    raise ArgumentError, "GeoJSON ต้องมีขอบเขต Polygon หรือ MultiPolygon อย่างน้อย 1 พื้นที่" if polygons.empty?

    factory.multi_polygon(polygons)
  rescue JSON::ParserError, RGeo::Error::RGeoError, Errno::ENOENT, IOError => error
    raise ArgumentError, "อ่านไฟล์ GeoJSON ไม่สำเร็จ: #{error.message}"
  end

  def polygon_parts(geometry)
    return [] unless geometry

    case geometry.geometry_type.type_name
    when "Polygon" then [geometry]
    when "MultiPolygon" then geometry.to_a
    else []
    end
  end

  def shapefile_boundary
    require "rgeo/shapefile"
    require "tmpdir"
    extension = File.extname(@boundary_file.original_filename).downcase
    if extension == ".shp"
      read_shapefile(@boundary_file.path)
    else
      require "zip"
      Dir.mktmpdir("access-area-shp") do |directory|
        Zip::File.open(@boundary_file.path) do |zip|
          zip.each do |entry|
            next if entry.directory?
            next unless %w[.shp .shx .dbf .prj].include?(File.extname(entry.name).downcase)

            entry.extract(File.join(directory, File.basename(entry.name))) { true }
          end
        end
        shape_path = Dir[File.join(directory, "*.shp")].first
        raise ArgumentError, "ZIP ต้องมีไฟล์ .shp" unless shape_path
        read_shapefile(shape_path)
      end
    end
  rescue Zip::Error => error
    raise ArgumentError, "อ่านไฟล์ ZIP ของ Shapefile ไม่สำเร็จ: #{error.message}"
  end

  def read_shapefile(path)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    polygons = []
    RGeo::Shapefile::Reader.open(path) do |reader|
      reader.each do |record|
        geometry = record.geometry
        next unless geometry
        converted = RGeo::Feature.cast(geometry, factory, :force_new)
        if converted.geometry_type.type_name == "Polygon"
          polygons << converted
        elsif converted.geometry_type.type_name == "MultiPolygon"
          converted.each { |polygon| polygons << polygon }
        end
      end
    end
    raise ArgumentError, "Shapefile ต้องมีขอบเขต Polygon หรือ MultiPolygon" if polygons.empty?
    factory.multi_polygon(polygons)
  rescue RGeo::Error::RGeoError, IOError, Errno::ENOENT => error
    raise ArgumentError, "อ่าน Shapefile ไม่สำเร็จ: #{error.message}"
  end
end

require "rexml/document"
require "zip"

class PlaceImportsController < ApplicationController
  before_action :require_subdistrict_admin!

  def create
    upload = params[:file]
    return render json: { error: "กรุณาเลือกไฟล์ KMZ หรือ Excel" }, status: :unprocessable_entity unless upload.respond_to?(:path)

    rows = case File.extname(upload.original_filename).downcase
           when ".kmz" then kmz_rows(upload.path)
           when ".xlsx", ".xls" then spreadsheet_rows(upload.path)
           else
             return render json: { error: "รองรับเฉพาะไฟล์ KMZ, XLSX และ XLS" }, status: :unprocessable_entity
           end

    imported = rows.filter_map { |row| save_place(row, upload.original_filename) }
    return render json: { error: "ไม่พบพิกัดสถานที่ที่อยู่ภายในตำบลของคุณ" }, status: :unprocessable_entity if imported.empty?

    render json: { imported: imported.size, places: imported }, status: :created
  rescue Zip::Error, REXML::ParseException, Roo::FileNotFound, Roo::HeaderRowNotFoundError => error
    render json: { error: "ไม่สามารถอ่านไฟล์นี้ได้: #{error.message}" }, status: :unprocessable_entity
  end

  private

  def require_subdistrict_admin!
    return if current_user.subdistrict_admin? || current_user.system_admin?

    render json: { error: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำตำบลเท่านั้นที่เพิ่มสถานที่ได้" }, status: :forbidden
  end

  def kmz_rows(path)
    kml = Zip::File.open(path) do |archive|
      kml_entry = archive.find { |entry| entry.name.downcase.end_with?(".kml") }
      raise Zip::Error, "ไม่พบไฟล์ KML ภายใน KMZ" unless kml_entry

      kml_entry.get_input_stream.read
    end

    document = REXML::Document.new(kml)
    REXML::XPath.match(document, "//*[local-name()='Placemark']").filter_map do |placemark|
      coordinates = REXML::XPath.first(placemark, ".//*[local-name()='Point']/*[local-name()='coordinates']")&.text
      lon, lat = coordinates.to_s.strip.split(",").first(2).map { |value| Float(value, exception: false) }
      next unless valid_coordinate?(lon, lat)

      {
        name: REXML::XPath.first(placemark, "./*[local-name()='name']")&.text.presence || "สถานที่นำเข้า",
        lon: lon,
        lat: lat,
        category: "สถานที่เพิ่มเติม"
      }
    end
  end

  def spreadsheet_rows(path)
    sheet = Roo::Spreadsheet.open(path).sheet(0)
    header = sheet.row(1).map { |value| value.to_s.strip.downcase }
    name_index = column_index(header, %w[name name_th ชื่อ ชื่อสถานที่ สถานที่]) || 0
    lat_index = column_index(header, %w[lat latitude ละติจูด])
    lon_index = column_index(header, %w[lon lng longitude ลองจิจูด])
    category_index = column_index(header, %w[category ประเภท])
    population_index = column_index(header, %w[population capacity จำนวนคน ประชากร])
    raise Roo::HeaderRowNotFoundError, "ต้องมีหัวคอลัมน์ lat และ lon" unless lat_index && lon_index

    (2..sheet.last_row).filter_map do |row_number|
      row = sheet.row(row_number)
      lon = Float(row[lon_index], exception: false)
      lat = Float(row[lat_index], exception: false)
      next unless valid_coordinate?(lon, lat)

      {
        name: row[name_index].to_s.strip.presence || "สถานที่นำเข้า",
        lon: lon,
        lat: lat,
        category: category_index ? row[category_index].to_s.strip.presence : "สถานที่เพิ่มเติม",
        estimated_population: population_index ? Integer(row[population_index], exception: false) : nil
      }
    end
  end

  def column_index(header, names)
    header.index { |column| names.include?(column) }
  end

  def valid_coordinate?(lon, lat)
    lon && lat && (-180..180).cover?(lon) && (-90..90).cover?(lat)
  end

  def save_place(row, source_file)
    subdistrict = Subdistrict.where("ST_Covers(boundary, ST_SetSRID(ST_Point(?, ?), 4326))", row[:lon], row[:lat]).first
    return unless subdistrict
    if current_user.access_area&.boundary
      return unless UserAccessArea.where(id: current_user.access_area.id)
        .where("ST_Covers(boundary, ST_SetSRID(ST_Point(?, ?), 4326))", row[:lon], row[:lat]).exists?
    elsif !current_user.system_admin? && subdistrict.id != current_user.subdistrict_id
      return
    end

    DynamicLayer.create!(
      layer_key: "important_place",
      name: row[:name],
      location: [row[:lon], row[:lat]],
      subdistrict_id: subdistrict.id,
      owner_user_id: current_user.id,
      shared_with_all: current_user.system_admin?,
      payload: {
        category: row[:category],
        estimated_population: row[:estimated_population],
        source: "upload",
        source_file: source_file
      }
    )
  end
end

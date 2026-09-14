require "csv"

class PopulationImportService
  def initialize(upload:, user:)
    @upload = upload
    @user = user
  end

  def import!
    require "roo"
    extension = File.extname(@upload.original_filename).downcase
    raise ArgumentError, "รองรับเฉพาะไฟล์ CSV, XLS และ XLSX" unless %w[.csv .xls .xlsx].include?(extension)

    table = if extension == ".csv"
              CSV.read(@upload.path, encoding: "bom|utf-8")
            else
              sheet = Roo::Spreadsheet.open(@upload.path).sheet(0)
              (1..sheet.last_row).map { |row_number| sheet.row(row_number) }
            end
    validate_headers!(table[1] || [])
    rows = table.drop(2).filter_map { |row| parse_row(row) }
    raise ArgumentError, "ไม่พบข้อมูลประชากรในไฟล์" if rows.empty?

    subdistrict_codes = rows.map { |row| row["subdistrict_code"] }.uniq
    raise ArgumentError, "ไฟล์ต้องมีข้อมูลตำบลเดียว" unless subdistrict_codes.one?
    subdistrict = Subdistrict.find_by(code: subdistrict_codes.first)
    raise ArgumentError, "ไม่พบรหัสตำบล #{subdistrict_codes.first} ในระบบ" unless subdistrict
    if !allowed_subdistrict?(subdistrict)
      raise ArgumentError, "คุณนำเข้าข้อมูลได้เฉพาะตำบลที่รับผิดชอบ"
    end

    summary = summarize(rows)
    PopulationDataset.create!(subdistrict:, user: @user, shared_with_all: @user.system_admin?, name: "ข้อมูลประชากร #{subdistrict.name_th}", source_file: @upload.original_filename, records: rows, summary:)
  end

  private

  def allowed_subdistrict?(subdistrict)
    return true if @user.system_admin?
    return @user.subdistrict_id == subdistrict.id unless @user.access_area&.boundary

    Subdistrict.where(id: subdistrict.id)
      .where("ST_Intersects(boundary, ?)", @user.access_area.boundary).exists?
  end

  def validate_headers!(headers)
    expected = { 9 => "อายุ 0", 13 => "65+", 14 => "ผู้ป่วยเรื้อรัง", 16 => "ผู้ป่วยติดเตียง", 17 => "ผู้พิการ", 19 => "ตั้งครรภ์" }
    invalid = expected.any? { |index, text| !headers[index].to_s.include?(text) }
    raise ArgumentError, "รูปแบบไฟล์ไม่ตรงกับ Template ข้อมูลประชากร" if invalid
  end

  def parse_row(row)
    subdistrict_code = code(row[4])
    village_code = code(row[6])
    return if subdistrict_code.blank? || village_code.blank?

    {
      "subdistrict_code" => subdistrict_code, "village_code" => village_code,
      "village_no" => integer(row[7]), "village_name" => row[8].to_s.strip,
      "age_0_14" => integer(row[9]), "age_15_24" => integer(row[10]), "age_25_54" => integer(row[11]),
      "age_55_64" => integer(row[12]), "age_65_plus" => integer(row[13]),
      "chronic" => integer(row[14]), "dialysis" => integer(row[15]), "bedridden" => integer(row[16]),
      "disabled" => integer(row[17]), "psychiatric" => integer(row[18]), "pregnant" => integer(row[19]), "total" => integer(row[20])
    }
  end

  def summarize(rows)
    keys = %w[total age_0_14 age_15_24 age_25_54 age_55_64 age_65_plus chronic dialysis bedridden disabled psychiatric pregnant]
    keys.index_with { |key| rows.sum { |row| row[key].to_i } }.merge("villages" => rows.size)
  end

  def code(value)
    value.to_s.sub(/\.0\z/, "").strip
  end

  def integer(value)
    value.to_f.round
  end
end

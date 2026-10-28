# An AI-assisted import of a user's own table (spreadsheet, PDF or photo of a table) into a new custom dataset.
# The AI reads the file into columns and rows, coordinates are parsed or geocoded inside the chosen subdistrict,
# the user corrects the table, then it becomes an ImportedDataset. Drafts expire after a day.
class SmartImport
  include Mongoid::Document
  include Mongoid::Timestamps

  STATUSES = %w[ready imported].freeze
  # How each column is used: coordinates are moved into latitude/longitude, location text feeds the geocoder.
  ROLES = {
    "none" => "ข้อมูลทั่วไป",
    "coordinates" => "พิกัด (lat, lon)",
    "latitude" => "ละติจูด",
    "longitude" => "ลองจิจูด",
    "location" => "ชื่อสถานที่/ที่อยู่ (ใช้หาพิกัด)"
  }.freeze
  GEO_STATUSES = {
    "file" => "พิกัดจากไฟล์",
    "geocoded" => "หาพิกัดจากชื่อสถานที่",
    "manual" => "แก้ไขเอง",
    "outside" => "อยู่นอกพื้นที่",
    "not_found" => "หาพิกัดไม่พบ",
    "none" => "ไม่มีข้อมูลตำแหน่ง"
  }.freeze
  MAX_ROWS = 5_000

  field :user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :status, type: String, default: "ready"
  field :name, type: String
  field :source_filename, type: String
  field :source_content_type, type: String
  field :source_file_id, type: BSON::ObjectId
  field :source_kind, type: String
  field :ai_model, type: String
  # [{ "key" => "c1", "label" => "ชื่อเกษตรกร", "type" => "text", "role" => "none" }]
  field :columns, type: Array, default: []
  # [{ "c1" => "...", "latitude" => 19.1, "longitude" => 100.9, "_geo" => "file", "_geo_note" => "..." }]
  field :rows, type: Array, default: []
  field :notes, type: Array, default: []
  field :result, type: Hash, default: {}
  field :dataset_id, type: BSON::ObjectId
  field :expires_at, type: Time

  index({ user_id: 1, created_at: -1 })
  index({ expires_at: 1 }, { expire_after_seconds: 0 })

  validates :user_id, :source_filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  before_create { self.expires_at ||= 1.day.from_now }
  before_destroy { DatasetGridFileStore.delete(source_file_id) if source_file_id && dataset_id.blank? }

  def subdistrict = subdistrict_id && Subdistrict.find_by(id: subdistrict_id)
  def imported? = status == "imported"
  def data_columns = columns.reject { |column| %w[coordinates latitude longitude].include?(column["role"]) }
  def located_rows = rows.count { |row| row["latitude"].present? && row["longitude"].present? && row["_geo"] != "outside" }

  def geo_summary
    rows.each_with_object(Hash.new(0)) { |row, counts| counts[row["_geo"].presence || "none"] += 1 }
  end

  def as_editor_json
    { id: id.to_s, name:, status:, subdistrict_id:, source_filename:, source_kind:, ai_model:, columns:, rows:, notes:,
      result:, roles: ROLES, geo_statuses: GEO_STATUSES, field_types: field_type_labels }
  end

  def field_type_labels = { "text" => "ข้อความ", "number" => "ตัวเลข", "integer" => "จำนวนเต็ม", "date" => "วันที่", "boolean" => "ใช่/ไม่ใช่" }
end

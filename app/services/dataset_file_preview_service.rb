require "csv"
require "tempfile"

class DatasetFilePreviewService
  SUPPORTED_EXTENSIONS = %w[.csv .xls .xlsx .pdf].freeze
  MAX_FILE_SIZE = 20.megabytes
  MAX_RECORDS = 25_000

  def initialize(upload)
    @upload = upload
  end

  def parse!
    extension = File.extname(@upload.original_filename).downcase
    raise ArgumentError, "รองรับเฉพาะไฟล์ CSV, XLS, XLSX และ PDF" unless SUPPORTED_EXTENSIONS.include?(extension)
    raise ArgumentError, "ไฟล์ต้องมีขนาดไม่เกิน 20 MB" if @upload.size > MAX_FILE_SIZE

    rows = extension == ".pdf" ? pdf_rows : tabular_rows(extension)
    rows = rows.reject { |row| row.values.all?(&:blank?) }
    raise ArgumentError, "ไม่พบข้อมูลในไฟล์" if rows.empty?
    raise ArgumentError, "นำเข้าได้ไม่เกิน #{MAX_RECORDS.to_fs(:delimited)} รายการ" if rows.size > MAX_RECORDS
    { headers: rows.flat_map(&:keys).uniq, rows: rows }
  rescue CSV::MalformedCSVError => error
    raise ArgumentError, "ไฟล์ CSV ไม่ถูกต้อง: #{error.message}"
  end

  private

  def tabular_rows(extension)
    return CSV.read(@upload.path, headers: true, encoding: "bom|utf-8").map(&:to_h) if extension == ".csv"

    require "roo"
    require "roo-xls" if extension == ".xls"
    sheet = Roo::Spreadsheet.open(@upload.path).sheet(0)
    headers = sheet.row(1).map { |header| header.to_s.strip }
    (2..sheet.last_row).map { |number| headers.zip(sheet.row(number)).to_h }
  end

  def pdf_rows
    require "pdf-reader"
    lines = PDF::Reader.new(@upload.path).pages.flat_map { |page| page.text.lines.map(&:strip) }.reject(&:blank?)
    raise ArgumentError, "PDF ไม่มีข้อความตารางที่อ่านได้" if lines.size < 2

    delimiter = lines.first.include?(",") ? /\s*,\s*/ : /\t|\s{2,}/
    headers = lines.shift.split(delimiter).map(&:strip)
    raise ArgumentError, "PDF ต้องมีแถวหัวตารางและแบ่งคอลัมน์ด้วยจุลภาค แท็บ หรือช่องว่าง" if headers.size < 2
    lines.filter_map do |line|
      values = line.split(delimiter, headers.size).map(&:strip)
      headers.zip(values).to_h if values.any?(&:present?)
    end
  rescue PDF::Reader::MalformedPDFError
    raise ArgumentError, "ไฟล์ PDF ไม่ถูกต้องหรือไม่สามารถอ่านข้อความได้"
  end
end

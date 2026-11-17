require "prawn"

class DatasetPdfReportService
  def initialize(title:, schema:, records:)
    @title = title
    @schema = schema
    @records = records
  end

  def generate
    font_path = "/usr/share/fonts/truetype/tlwg/Garuda.ttf"
    raise "Thai PDF font is missing" unless File.file?(font_path)

    pdf = Prawn::Document.new(page_size: "A4", margin: 40)
    pdf.font_families.update("Thai" => { normal: font_path })
    pdf.font("Thai")
    pdf.text(@title, size: 18, style: :normal, color: "294438")
    pdf.text("ข้อมูลปัจจุบัน · #{@records.length} รายการ · #{Time.zone.today.strftime('%d/%m/%Y')}", size: 10)
    pdf.move_down(16)
    @records.each_with_index do |record, index|
      pdf.start_new_page if pdf.cursor < 90
      pdf.fill_color("EDF2EE")
      pdf.fill_rectangle([0, pdf.cursor], pdf.bounds.width, 22)
      pdf.fill_color("294438")
      pdf.text_box("รายการ #{index + 1}", at: [8, pdf.cursor - 3], width: pdf.bounds.width - 16, height: 18, size: 11)
      pdf.move_down(28)
      @schema.each do |field|
        value = record[field["key"]]
        value = value.to_json if value.is_a?(Hash) || value.is_a?(Array)
        pdf.text("#{field['label']}: #{value.presence || '—'}", size: 10, color: "2C3930")
        pdf.move_down(3)
      end
      pdf.move_down(12)
    end
    pdf.text("ยังไม่มีข้อมูล", size: 11) if @records.empty?
    pdf.number_pages("<page>/<total>", at: [pdf.bounds.right - 55, 0], size: 9)
    pdf.render
  end
end

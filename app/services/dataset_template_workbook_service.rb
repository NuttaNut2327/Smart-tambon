require "cgi"
require "zip"

class DatasetTemplateWorkbookService
  def initialize(data_type:, schema:)
    @data_type = data_type
    @schema = schema
  end

  def generate
    Zip::OutputStream.write_buffer do |zip|
      write(zip, "[Content_Types].xml", content_types)
      write(zip, "_rels/.rels", package_relationships)
      write(zip, "xl/workbook.xml", workbook)
      write(zip, "xl/_rels/workbook.xml.rels", workbook_relationships)
      write(zip, "xl/styles.xml", styles)
      write(zip, "xl/worksheets/sheet1.xml", data_sheet)
      write(zip, "xl/worksheets/sheet2.xml", instruction_sheet)
    end.string
  end

  private

  def write(zip, path, content)
    zip.put_next_entry(path)
    zip.write(content)
  end

  def xml(value) = CGI.escapeHTML(value.to_s)

  def column_name(index)
    name = +""
    while index.positive?
      index -= 1
      name.prepend((65 + (index % 26)).chr)
      index /= 26
    end
    name
  end

  def inline_cell(reference, value, style = nil)
    style_attribute = style ? %( s="#{style}") : ""
    %(<c r="#{reference}" t="inlineStr"#{style_attribute}><is><t>#{xml(value)}</t></is></c>)
  end

  def content_types
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      </Types>
    XML
  end

  def package_relationships
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      </Relationships>
    XML
  end

  def workbook
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="ข้อมูลนำเข้า" sheetId="1" r:id="rId1"/><sheet name="คำแนะนำ" sheetId="2" r:id="rId2"/></sheets>
      </workbook>
    XML
  end

  def workbook_relationships
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def styles
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Aptos"/></font></fonts>
        <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF294438"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf></cellXfs>
      </styleSheet>
    XML
  end

  def data_sheet
    last_column = column_name(@schema.length)
    headers = @schema.each_with_index.map { |field, index| inline_cell("#{column_name(index + 1)}1", field["label"], 1) }.join
    columns = @schema.each_index.map { |index| %(<col min="#{index + 1}" max="#{index + 1}" width="22" customWidth="1"/>) }.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <cols>#{columns}</cols><sheetData><row r="1" ht="24" customHeight="1">#{headers}</row></sheetData>
        <autoFilter ref="A1:#{last_column}1"/>
      </worksheet>
    XML
  end

  def instruction_sheet
    rows = [["วิธีใช้งาน Template"],
      ["1. กรอกข้อมูลในชีต ‘ข้อมูลนำเข้า’ โดยเริ่มจากแถวที่ 2"],
      ["2. ห้ามแก้ไขชื่อหัวคอลัมน์ เพื่อให้ระบบจับคู่ข้อมูลอัตโนมัติ"],
      ["3. ช่องที่ระบุว่าไม่บังคับสามารถเว้นว่างได้"],
      ["4. ต้องมีข้อมูลอย่างน้อย 1 แถวก่อนอัปโหลด"],
      ["ประเภทข้อมูล", ImportedDataset::TYPE_LABELS.fetch(@data_type, @data_type)]]
    sheet_rows = rows.each_with_index.map do |values, row_index|
      cells = values.each_with_index.map { |value, column_index| inline_cell("#{column_name(column_index + 1)}#{row_index + 1}", value, row_index.zero? ? 1 : nil) }.join
      %(<row r="#{row_index + 1}">#{cells}</row>)
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="70" customWidth="1"/><col min="2" max="2" width="30" customWidth="1"/></cols><sheetData>#{sheet_rows}</sheetData></worksheet>
    XML
  end
end

require "csv"

module SmartImports
  # Reads an uploaded table into { title:, columns: [{ label, type, role }], rows: [[...]] } with help from the LLM.
  # Spreadsheets: the LLM only sees the first rows to find the header row and column meanings; every row is then
  # mapped in Ruby, so large files cost one small call. PDFs with a text layer: the LLM structures the text.
  # Photos and scanned PDFs (pages rendered to images in the browser): the LLM reads the images page by page.
  class Extractor
    class Error < StandardError; end

    SPREADSHEET = %w[.xlsx .xls .csv].freeze
    IMAGE_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp" }.freeze
    SUPPORTED = SPREADSHEET + %w[.pdf] + IMAGE_TYPES.keys
    MAX_FILE_SIZE = 20.megabytes
    MAX_PAGES = 10
    SAMPLE_ROWS = 30

    RULES = <<~TEXT.freeze
      กติกา:
      - ตอบเป็น JSON อย่างเดียว ไม่มีข้อความอื่น และห้ามใช้ markdown
      - คัดลอกค่าในเซลล์ตามที่เห็นจริง ห้ามแต่ง เดา หรือแปลค่า ถ้าอ่านไม่ออกให้ใส่ "" (สตริงว่าง)
      - type ของคอลัมน์: "text" | "number" | "integer" | "date"
      - role ของคอลัมน์:
        "coordinates" = มีละติจูดและลองจิจูดรวมในช่องเดียว (เช่น 19.13, 100.91 หรือ 19°08'10"N 100°55'05"E)
        "latitude" / "longitude" = แยกคนละคอลัมน์
        "location" = ชื่อสถานที่ ที่อยู่ ถนน หมู่บ้าน ที่ใช้ค้นหาตำแหน่งได้
        "none" = อื่น ๆ
      - ตัวเลขไทย (๐-๙) ให้เขียนเป็นเลขอารบิก (0-9)
      - ไม่ต้องใส่คอลัมน์ลำดับที่ (ลำดับ, ที่, No.) ถ้าเป็นแค่เลขเรียง
    TEXT

    def initialize(upload:, llm:, page_images: [])
      @upload = upload
      @llm = llm
      @page_images = Array(page_images)
      @extension = File.extname(upload.original_filename.to_s).downcase
    end

    def call
      raise Error, "รองรับไฟล์ XLSX, XLS, CSV, PDF และรูปภาพ (PNG, JPG, WEBP)" unless SUPPORTED.include?(@extension)
      raise Error, "ไฟล์ต้องมีขนาดไม่เกิน 20 MB" if @upload.size > MAX_FILE_SIZE

      result =
        if SPREADSHEET.include?(@extension) then spreadsheet
        elsif @extension == ".pdf" then pdf
        else images([{ data: File.binread(@upload.path), media_type: IMAGE_TYPES.fetch(@extension) }], kind: "image")
        end
      result[:title] = clean(result[:title])
      result[:columns].each { |column| column[:label] = clean(column[:label]) }
      result[:rows] = result[:rows].map { |row| Array(row).map { |value| clean(value) } }.reject { |row| row.all?(&:blank?) }
      raise Error, "ไม่พบข้อมูลตารางในไฟล์" if result[:columns].empty? || result[:rows].empty?

      result
    end

    private

    def spreadsheet
      grid = read_grid
      raise Error, "ไม่พบข้อมูลในไฟล์" if grid.empty?

      sample = grid.first(SAMPLE_ROWS).each_with_index.map { |row, index| "#{index}: #{row.to_json}" }.join("\n")
      plan = ask(<<~PROMPT)
        ต่อไปนี้คือแถวแรก ๆ ของสเปรดชีต (เลขหน้าบรรทัดคือ index ของแถว เริ่มที่ 0 แต่ละแถวเป็น JSON array ของเซลล์)
        หาแถวหัวตาราง และอธิบายแต่ละคอลัมน์ที่มีข้อมูล
        #{RULES}
        ตอบรูปแบบ: {"title": "ชื่อตารางถ้ามี", "header_row": 2, "columns": [{"index": 1, "label": "ชื่อคอลัมน์", "type": "text", "role": "none"}]}
        ถ้าไม่มีแถวหัวตาราง ให้ header_row = -1 และตั้งชื่อคอลัมน์ให้สื่อความหมาย

        #{sample}
      PROMPT
      header = plan["header_row"].to_i
      columns = Array(plan["columns"]).filter_map do |column|
        index = Integer(column["index"], exception: false)
        next if index.nil? || index.negative?

        normalize_column(column).merge(index:)
      end
      raise Error, "AI แยกคอลัมน์จากไฟล์ไม่ได้" if columns.empty?

      rows = grid.drop(header + 1).map { |row| columns.map { |column| row[column[:index]] } }
      { title: plan["title"].to_s.strip, columns: columns.map { |column| column.except(:index) }, rows:, kind: "spreadsheet" }
    end

    def read_grid
      rows =
        if @extension == ".csv"
          CSV.read(@upload.path, encoding: "bom|utf-8")
        else
          require "roo"
          require "roo-xls" if @extension == ".xls"
          book = Roo::Spreadsheet.open(@upload.path, extension: @extension.delete(".").to_sym)
          sheet = book.sheets.map { |name| book.sheet(name) }.find { |candidate| candidate.last_row.to_i.positive? }
          sheet ? (sheet.first_row..sheet.last_row).map { |number| sheet.row(number) } : []
        end
      rows.map { |row| Array(row).map { |value| cell_text(value) } }.reject { |row| row.all?(&:blank?) }.first(SmartImport::MAX_ROWS + SAMPLE_ROWS)
    rescue CSV::MalformedCSVError, Zip::Error, Ole::Storage::FormatError => error
      raise Error, "อ่านไฟล์ไม่ได้: #{error.message.truncate(120)}"
    end

    def cell_text(value)
      case value
      when Float then value == value.to_i && value.abs < 1e15 ? value.to_i.to_s : value.to_s
      when Date, Time, DateTime then value.to_date.iso8601
      else value.to_s.tr("๐-๙", "0-9").strip
      end
    end

    def pdf
      text = pdf_text
      return text_table(text) if text.gsub(/\s+/, "").length >= 40
      raise Error, "PDF นี้เป็นภาพสแกน — กรุณาลองอัปโหลดใหม่ (ระบบจะแปลงหน้า PDF เป็นภาพในเบราว์เซอร์)" if @page_images.empty?

      images(@page_images, kind: "scanned_pdf")
    end

    def pdf_text
      require "pdf-reader"
      PDF::Reader.new(@upload.path).pages.first(MAX_PAGES).map(&:text).join("\n\f\n")
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      ""
    end

    def text_table(text)
      data = ask(<<~PROMPT)
        ต่อไปนี้คือข้อความที่ดึงจากไฟล์ PDF ซึ่งมีตารางอยู่ (การจัดแนวคอลัมน์อาจเพี้ยน) แยกออกมาเป็นตาราง
        #{RULES}
        #{table_format}

        <pdf>
        #{text.truncate(60_000)}
        </pdf>
      PROMPT
      table_from(data, kind: "pdf_text")
    end

    # Reads each page image; later pages reuse the first page's columns so the rows line up.
    def images(images, kind:)
      raise Error, "รองรับได้ไม่เกิน #{MAX_PAGES} หน้า" if images.size > MAX_PAGES

      columns = nil
      title = ""
      rows = []
      images.each_with_index do |image, page|
        known = columns && "หน้านี้เป็นตารางต่อจากหน้าก่อน ใช้คอลัมน์เดิมตามลำดับนี้: #{columns.map { |column| column[:label] }.to_json} ถ้าหน้านี้มีแถวหัวตารางซ้ำให้ข้ามไป"
        data = ask(<<~PROMPT, images: [image])
          อ่านตารางในภาพนี้ (หน้า #{page + 1}/#{images.size}) ทำ OCR ทีละเซลล์อย่างระมัดระวัง รวมภาษาไทย ตัวเลข และพิกัด
          ถ้าข้อความในเซลล์ล้นไปทับเส้นของคอลัมน์ถัดไป ให้ถือว่าเป็นค่าของเซลล์ต้นทาง
          #{RULES}
          #{known}
          #{table_format}
        PROMPT
        table = table_from(data, kind:)
        columns ||= table[:columns]
        title = table[:title] if title.blank?
        rows.concat(table[:rows].map { |row| row.first(columns.size) + Array.new([columns.size - row.size, 0].max, "") })
      end
      { title:, columns: columns || [], rows:, kind: }
    end

    def table_format
      'ตอบรูปแบบ: {"title": "ชื่อตารางถ้ามี", "columns": [{"label": "ชื่อคอลัมน์", "type": "text", "role": "none"}], "rows": [["ค่าคอลัมน์ 1", "ค่าคอลัมน์ 2"]]} โดยแต่ละแถวมีจำนวนค่าเท่ากับจำนวน columns'
    end

    def table_from(data, kind:)
      columns = Array(data["columns"]).map { |column| normalize_column(column) }
      rows = Array(data["rows"]).select { |row| row.is_a?(Array) }
      { title: data["title"].to_s.strip, columns:, rows:, kind: }
    end

    def normalize_column(column)
      { label: column["label"].to_s.strip.presence || "คอลัมน์",
        type: column["type"].to_s.presence_in(%w[text number integer date]) || "text",
        role: column["role"].to_s.presence_in(SmartImport::ROLES.keys) || "none" }
    end

    def ask(prompt, images: [])
      message = images.any? ? @llm.image_message(prompt, images) : @llm.user_message(prompt)
      response = @llm.chat(system: "คุณคือผู้ช่วยแปลงเอกสารตารางภาษาไทยเป็นข้อมูลโครงสร้าง ตอบเป็น JSON ที่ถูกต้องเท่านั้น", tools: [], messages: [message])
      parse_json(response.text)
    rescue Ai::Llm::Error => error
      raise Error, "AI อ่านไฟล์ไม่สำเร็จ: #{error.message}"
    end

    def parse_json(text)
      json = text.to_s[/\{.*\}/m] or raise Error, "AI ไม่ได้ตอบกลับเป็นตาราง"
      JSON.parse(json)
    rescue JSON::ParserError
      begin
        JSON.parse(json.gsub(/,\s*([\]}])/, '\1'))
      rescue JSON::ParserError
        raise Error, "AI ตอบกลับในรูปแบบที่อ่านไม่ได้ (คำตอบอาจยาวเกินไป ลองแบ่งไฟล์เป็นส่วนเล็กลง)"
      end
    end

    # Thai digits (๐–๙) become 0–9 so numbers and coordinates parse and sort.
    def clean(value)
      value.to_s.tr("๐-๙", "0-9").gsub(/[[:space:]]+/, " ").strip
    end
  end
end

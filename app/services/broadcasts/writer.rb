module Broadcasts
  # Asks the configured LLM to turn the user's prompt plus the real data into a news broadcast:
  # a title, short bullet points (for chat/social posts) and a spoken announcer script (for TTS).
  class Writer
    class Error < StandardError; end

    Result = Struct.new(:title, :bullets, :script, :model, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      คุณคือผู้ประกาศข่าวเสียงตามสายขององค์การบริหารส่วนตำบล (อบต.) เขียนข่าวให้ชาวบ้านทุกวัยฟังเข้าใจง่าย
      กติกาสำคัญ:
      1. ใช้เฉพาะข้อเท็จจริงที่อยู่ใน <data> เท่านั้น ห้ามแต่งตัวเลข วันเวลา สถานที่ ชื่อ หรือเหตุการณ์ที่ไม่มีในข้อมูล
         ถ้าหัวข้อใดไม่มีข้อมูล ให้ข้ามไป หรือบอกว่า "ยังไม่มีข้อมูล" — ห้ามเดา
      2. ใช้ภาษาไทยง่าย ประโยคสั้น น้ำเสียงสุภาพเป็นกันเองแบบผู้ประกาศข่าวในหมู่บ้าน หลีกเลี่ยงศัพท์เทคนิคและอักษรย่อ
      3. ใน script ให้เขียนตัวเลข หน่วย และเวลาแบบที่อ่านออกเสียงได้ทันที เช่น "สามสิบสององศาเซลเซียส", "เจ็ดโมงเช้า",
         "ไมโครกรัมต่อลูกบาศก์เมตร" ไม่ใช้สัญลักษณ์ อีโมจิ หรือ markdown
      4. ห้ามเปิดเผยข้อมูลส่วนบุคคล
      4.1 ถ้ามี weather_forecast.heavy_rain_days, gistda_hotspots_24h หรือ gistda_flood ที่มีรายการ ให้แจ้งเตือนชัดเจนพร้อมวันและสถานที่ตามข้อมูล
          และบอกที่มาของข้อมูล (เช่น "ข้อมูลจาก GISTDA") ถ้าจำนวนเป็นศูนย์ให้บอกสั้น ๆ ว่าไม่พบ
          จุดความร้อน: count_24h คือภายใน 24 ชั่วโมง ส่วน count_latest_day คือรอบดาวเทียมล่าสุดของ GISTDA ให้บอกเวลาตรวจพบ (detected) ตามจริง
      4.2 disaster_history เป็นสถิติภัยพิบัติในอดีต ไม่ใช่การพยากรณ์ ให้พูดว่า "ในอดีตช่วงสัปดาห์นี้เคย…" ห้ามพูดว่าจะเกิดแน่นอน
          places_hit_after_similar_rain คือพื้นที่ที่เคยเกิดน้ำท่วม/ดินถล่มเมื่อฝนสามวันน้อยกว่าหรือเท่ากับฝนที่คาดการณ์ครั้งนี้ ให้เตือนพื้นที่เหล่านี้ก่อน
          ถ้ามี demo_data ต้องบอกผู้ฟังชัดเจนว่าเป็นข้อมูลจำลองเพื่อสาธิต
      5. ตอบกลับเป็น JSON เท่านั้น ไม่มีข้อความอื่น ตามรูปแบบ:
         {"title": "หัวข้อข่าวสั้น ๆ", "bullets": ["ประเด็นสั้น 1", "ประเด็นสั้น 2"], "script": "บทอ่านออกเสียงแบบย่อหน้า"}
    PROMPT

    def self.call(program, context) = new(program, context).call

    def initialize(program, context)
      @program = program
      @context = context
    end

    def call
      llm = Ai::Llm.for(@program.ai_provider)
      response = llm.chat(system: SYSTEM_PROMPT, tools: [], messages: [llm.user_message(user_message)])
      parsed = parse(response.text)
      Result.new(title: parsed["title"].to_s.strip.truncate(150), bullets: Array(parsed["bullets"]).map { |item| item.to_s.strip }.compact_blank.first(12),
                 script: parsed["script"].to_s.strip, model: response.model)
    rescue Ai::Llm::Error => error
      raise Error, error.message
    end

    private

    def user_message
      <<~MESSAGE
        คำสั่งจากเจ้าหน้าที่ อบต.:
        #{@program.prompt}

        ความยาวบทอ่าน (script) ไม่เกินประมาณ #{@program.max_words} คำ (อ่านจบในราว #{reading_minutes} นาที) และ bullets ไม่เกิน 8 ข้อ
        เลือกเฉพาะข้อความที่สำคัญที่สุดก่อน ถ้าเนื้อหาเกินความยาวให้ตัดเรื่องรองออก อย่าอ่านเร็วขึ้นหรือย่อจนเสียความหมาย

        <data>
        #{JSON.pretty_generate(@context)}
        </data>
      MESSAGE
    end

    def reading_minutes
      minutes = (@program.max_words.to_f / BroadcastProgram::WORDS_PER_MINUTE).round(1)
      minutes == minutes.to_i ? minutes.to_i : minutes
    end

    # Accepts bare JSON or JSON inside a code fence; falls back to treating the whole reply as the script.
    def parse(text)
      json = text.to_s[/\{.*\}/m]
      data = json && (JSON.parse(json) rescue JSON.parse(escape_raw_newlines(json)))
      raise JSON::ParserError unless data.is_a?(Hash) && (data["script"].present? || data["bullets"].present?)

      data
    rescue JSON::ParserError
      raise Error, "AI ตอบกลับว่างเปล่า" if text.blank?

      { "title" => "#{@program.name} #{@context['today']}", "bullets" => [], "script" => text.strip }
    end

    # Models often put real line breaks inside the "script" string, which strict JSON rejects; escape them.
    def escape_raw_newlines(json)
      in_string = escaped = false
      json.each_char.with_object(+"") do |char, out|
        if in_string && !escaped && char == "\n" then out << "\\n"
        elsif in_string && !escaped && char == "\r" then next
        elsif in_string && !escaped && char == "\t" then out << "\\t"
        else
          out << char
          in_string = !in_string if char == '"' && !escaped
        end
        escaped = in_string && char == "\\" && !escaped
      end
    end
  end
end

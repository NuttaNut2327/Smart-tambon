module Ai
  # Answers one chat turn: replays the session history in the provider's own format, lets the model call the
  # data tools, and records the answer with its charts (artifacts) and the queries behind them.
  class Agent
    MAX_ROUNDS = 8
    LLM_ROWS = 100
    CHART_KINDS = %w[bar horizontal_bar line area pie doughnut table kpi].freeze

    def initialize(user:, provider:)
      @user = user
      @provider = provider
      @catalog = DataCatalog.new(user)
      @engine = QueryEngine.new(@catalog)
    end

    def reply(session, text)
      llm = Llm.for(@provider)
      messages = history(session, llm)
      append_user(messages, llm, text)
      transcript = []
      queries = []
      artifacts = []
      usage = Hash.new(0)
      response = nil

      (MAX_ROUNDS + 1).times do |round|
        response = llm.chat(system: system_prompt, tools: tool_definitions, messages: messages)
        response.usage.each { |key, value| usage[key] += value.to_i }
        messages << response.assistant_message
        step = { "assistant" => response.assistant_message, "results" => [] }
        transcript << step
        break if response.tool_calls.empty?

        # Past the round limit every call is answered with an error so the model writes its answer instead.
        results = response.tool_calls.map do |call|
          next run_tool(call, queries, artifacts) if round < MAX_ROUNDS

          { id: call.id, content: { error: "ถึงจำนวนครั้งสูงสุดของการดึงข้อมูลแล้ว ให้สรุปคำตอบจากข้อมูลที่มี" }.to_json, error: true }
        end
        step["results"] = llm.tool_results(results)
        messages.concat(step["results"])
      end

      { content: response.text.presence || "(ไม่มีคำตอบจาก AI)", artifacts: artifacts, queries: queries, transcript: transcript,
        api_format: llm.format, model: response.model, usage: usage.to_h }
    end

    # Fresh narrative for a re-run snippet: one tool-free call over the new rows.
    def summarize(question:, report:, artifacts:)
      llm = Llm.for(@provider)
      data = artifacts.map { |artifact| { title: artifact["title"], columns: artifact["columns"], rows: Array(artifact["rows"]).first(LLM_ROWS) } }
      prompt = <<~PROMPT
        คำถามเดิม: #{question.presence || '-'}
        รายงานฉบับก่อน (ตัวเลขอาจล้าสมัย):
        #{report.to_s.truncate(4000)}

        ข้อมูลล่าสุดจากการรันใหม่ (JSON):
        #{data.to_json.truncate(60_000)}

        เขียนรายงานสรุปฉบับใหม่ภาษาไทยด้วย Markdown โดยใช้เฉพาะตัวเลขจากข้อมูลล่าสุดข้างบน คงโครงสร้างหัวข้อเดิมไว้ถ้าเหมาะสม
        และวางเครื่องหมาย [[artifact:N]] (N คือลำดับกราฟเริ่มที่ 1) ตรงตำแหน่งที่ควรแสดงกราฟ
      PROMPT
      llm.chat(system: system_prompt, tools: [], messages: [llm.user_message(prompt)]).text
    end

    # Re-runs kept artifact specs with this user's scope (and an optional period), returning rows to draw.
    def run_artifacts(definitions, params: {})
      definitions.map do |definition|
        definition = definition.to_h.stringify_keys
        result = @engine.run(definition["spec"], params: params)
        definition.merge("columns" => result.columns, "rows" => result.rows, "total" => result.total, "error" => nil)
      rescue QueryEngine::InvalidSpec => error
        definition.merge("columns" => [], "rows" => [], "error" => error.message)
      end
    end

    private

    def history(session, llm)
      session.messages.asc(:seq).to_a.each_with_object([]) do |message, list|
        if message.role == "user"
          append_user(list, llm, message.content)
        elsif message.api_format == llm.format && message.transcript.present?
          message.transcript.deep_dup.each { |step| list << step["assistant"]; list.concat(Array(step["results"])) }
        elsif message.content.present? && message.error.blank?
          list << llm.assistant_text(message.content.gsub(/\[\[artifact:\d+\]\]/, "[กราฟ]"))
        end
      end
    end

    # Providers expect user/assistant turns to alternate, so a user turn that follows another user turn (an
    # earlier failed answer, or Claude tool results) is folded into it rather than sent as a second message.
    def append_user(list, llm, text)
      last = list.last
      return list << llm.user_message(text) unless last && last["role"] == "user"

      if last["content"].is_a?(Array)
        last["content"] += [{ "type" => "text", "text" => text }]
      else
        last["content"] = "#{last['content']}\n\n#{text}"
      end
    end

    def run_tool(call, queries, artifacts)
      content = case call.name
                when "query_data" then tool_query(call.input, queries)
                when "show_chart" then tool_chart(call.input, queries, artifacts)
                when "list_imported_datasets" then { datasets: @catalog.imported_datasets }
                when "describe_source" then tool_describe(call.input)
                else raise QueryEngine::InvalidSpec, "ไม่รู้จักเครื่องมือ #{call.name}"
                end
      { id: call.id, content: content.to_json }
    rescue QueryEngine::InvalidSpec => error
      { id: call.id, content: { error: error.message }.to_json, error: true }
    rescue StandardError => error
      Rails.logger.error("AI tool #{call.name} failed: #{error.class}: #{error.message}")
      { id: call.id, content: { error: "เกิดข้อผิดพลาดภายในขณะดึงข้อมูล" }.to_json, error: true }
    end

    def tool_query(input, queries)
      spec = input.to_h.deep_stringify_keys
      result = @engine.run(spec)
      queries << { "name" => "q#{queries.size + 1}", "spec" => spec, "total" => result.total }
      result.as_json.merge(rows: result.rows.first(LLM_ROWS), rows_shown: [result.rows.size, LLM_ROWS].min)
    rescue QueryEngine::InvalidSpec => error
      queries << { "name" => "q#{queries.size + 1}", "spec" => spec, "error" => error.message }
      raise
    end

    def tool_chart(input, queries, artifacts)
      input = input.to_h.deep_stringify_keys
      kind = CHART_KINDS.include?(input["kind"]) ? input["kind"] : "bar"
      spec = input["query"].to_h
      raise QueryEngine::InvalidSpec, "show_chart ต้องมี query" if spec.blank?

      result = @engine.run(spec)
      queries << { "name" => "q#{queries.size + 1}", "spec" => spec, "total" => result.total }
      x = input["x"].presence || result.columns.first
      y = Array(input["y"]).presence || (result.columns - [x, input["series_by"]]).first(1)
      missing = ([x, input["series_by"]].compact + y) - result.columns
      raise QueryEngine::InvalidSpec, "คอลัมน์ #{missing.join(', ')} ไม่มีในผลลัพธ์ (มี: #{result.columns.join(', ')})" if missing.any? && kind != "table"

      key = artifacts.size + 1
      artifacts << { "key" => key, "title" => input["title"].presence || "กราฟ #{key}", "kind" => kind, "spec" => spec,
                     "x" => x, "y" => y, "series_by" => input["series_by"].presence, "columns" => result.columns,
                     "rows" => result.rows, "total" => result.total }
      { marker: "[[artifact:#{key}]]", note: "วาง marker นี้ในคำตอบตรงตำแหน่งที่ต้องการแสดงกราฟ", columns: result.columns,
        rows_preview: result.rows.first(30), total: result.total }
    end

    def tool_describe(input)
      source = @catalog.source(input.to_h.stringify_keys["source"]) or raise QueryEngine::InvalidSpec, "ไม่พบแหล่งข้อมูลนี้ หรือบัญชีนี้ไม่มีสิทธิ์เข้าถึง"

      source.as_catalog_json
    end

    def system_prompt
      @system_prompt ||= <<~PROMPT
        คุณคือ "ผู้ช่วย AI" ของระบบ #{SystemSetting.current.system_short_name} สำหรับเจ้าหน้าที่องค์การบริหารส่วนตำบล (อบต.)
        หน้าที่: ตอบคำถาม วิเคราะห์ และจัดทำรายงานจากข้อมูลภายในระบบของบัญชีนี้เท่านั้น

        หลักการ
        - ตอบเป็นภาษาไทย กระชับ ชัดเจน ใช้ Markdown (หัวข้อ ##, รายการ, ตาราง) ได้
        - ตัวเลขทุกตัวต้องมาจากผลของเครื่องมือ query_data หรือ show_chart ในการสนทนานี้ ห้ามเดาหรือแต่งข้อมูล
          ถ้าข้อมูลไม่มีหรือไม่พอ ให้บอกตรง ๆ ว่าไม่มีข้อมูลส่วนไหน
        - ระบบจำกัดข้อมูลตามสิทธิ์ของบัญชีให้อยู่แล้ว ห้ามอ้างหรือเดาข้อมูลของ อบต. อื่น
          ไม่ต้องกรองด้วยตำบล/อำเภอเอง เว้นแต่ผู้ใช้ระบุพื้นที่ย่อย และใช้ค่าตามที่ปรากฏในข้อมูลจริง (เช่น "ป่ากลาง" ไม่ใช่ "ต.ป่ากลาง")
        - ถ้าผลลัพธ์มี hints แปลว่าค่าที่กรองไม่มีในข้อมูล ให้แก้ค่าตาม hints แล้วค้นใหม่ ก่อนสรุปว่าไม่มีข้อมูล
        - เมื่อคำตอบเหมาะกับกราฟหรือตาราง (แนวโน้มตามเวลา เปรียบเทียบหมวด สัดส่วน) ให้เรียก show_chart แล้ววาง marker
          ที่ได้ เช่น [[artifact:1]] ไว้ในคำตอบตรงตำแหน่งที่ต้องการ ไม่ต้องวาดตารางซ้ำกับกราฟ
        - เมื่อผู้ใช้ขอ "รายงาน" ให้เขียนเป็นรายงานมีโครงสร้าง: ## สรุปสาระสำคัญ, ## รายละเอียด (พร้อมกราฟ), ## ข้อสังเกต/ข้อเสนอแนะ
        - ใช้ query แบบ group_by + measures เพื่อสรุปตัวเลข แทนการดึงรายการทั้งหมด ดึงรายการ (columns) เฉพาะเมื่อต้องการดูรายละเอียด
        - ข้อมูลชุดที่นำเข้าเอง (แหล่งข้อมูล dataset:<id>) ให้เรียก list_imported_datasets และ describe_source ก่อนเพื่อดูฟิลด์
        - ปีงบประมาณไทยเริ่ม 1 ตุลาคม และใช้ปี พ.ศ.

        รูปแบบ query (ใช้ใน query_data และใน query ของ show_chart)
        { "source": "<id>", "filters": [{"field","op","value"}], "group_by": [{"field","bucket"}],
          "measures": [{"agg","field","label"}], "columns": ["field", ...], "sort": {"by","dir"}, "limit": 20 }
        - op: #{QueryEngine::OPS.join(', ')} (between ใช้ value เป็น [ต่ำสุด, สูงสุด])
        - agg: #{QueryEngine::AGGS.join(', ')} (count ไม่ต้องระบุ field)
        - bucket สำหรับฟิลด์วันที่: #{QueryEngine::BUCKETS.join(', ')}
        - ค่าในฟิลด์ประเภท enum เป็นข้อความภาษาไทยตามรายการ values ให้กรองด้วยข้อความนั้นตรงตัว
        - วันที่ใช้รูปแบบ ISO เช่น "2026-10-01" ผลลัพธ์แต่ละแถวใช้ชื่อคอลัมน์ตาม label ของ group/measure (ถ้าไม่ตั้งจะเป็น field หรือ agg_field)
        - show_chart: x = คอลัมน์แกนนอน/หมวด, y = รายการคอลัมน์ตัวเลข, series_by = คอลัมน์แยกชุดข้อมูล (ถ้ามี)
          kind: #{CHART_KINDS.join(', ')} (kpi = ตัวเลขเด่นจากแถวแรก)

        แหล่งข้อมูลในระบบ (catalog)
        #{@catalog.as_catalog_json.to_json}

        บริบทผู้ใช้
        #{@catalog.area_summary.to_json}
        วันนี้: #{Date.current.iso8601} (เวลาประเทศไทย)
      PROMPT
    end

    def tool_definitions
      query_schema = {
        type: "object",
        properties: {
          source: { type: "string", description: "id ของแหล่งข้อมูลใน catalog หรือ dataset:<id>" },
          filters: { type: "array", items: { type: "object", properties: { field: { type: "string" }, op: { type: "string", enum: QueryEngine::OPS }, value: {} }, required: %w[field op] } },
          group_by: { type: "array", items: { type: "object", properties: { field: { type: "string" }, bucket: { type: "string", enum: QueryEngine::BUCKETS }, label: { type: "string" } }, required: %w[field] } },
          measures: { type: "array", items: { type: "object", properties: { agg: { type: "string", enum: QueryEngine::AGGS }, field: { type: "string" }, label: { type: "string" } }, required: %w[agg] } },
          columns: { type: "array", items: { type: "string" }, description: "ฟิลด์ที่ต้องการในโหมดรายการ (ไม่มี group_by)" },
          sort: { type: "object", properties: { by: { type: "string" }, dir: { type: "string", enum: %w[asc desc] } } },
          limit: { type: "integer", minimum: 1, maximum: QueryEngine::MAX_LIMIT }
        },
        required: %w[source]
      }
      [
        { name: "query_data", schema: query_schema,
          description: "ค้นหา กรอง จัดกลุ่ม และสรุปข้อมูลจากแหล่งข้อมูลในระบบ (เฉพาะขอบเขตของบัญชีนี้) คืนค่า columns, rows และ total (จำนวนแถวที่ตรงเงื่อนไขก่อนจัดกลุ่ม)" },
        { name: "show_chart",
          description: "สร้างกราฟหรือตารางเพื่อแสดงให้ผู้ใช้เห็นในคำตอบ ระบบจะรัน query เองแล้วคืน marker [[artifact:N]] ให้วางในคำตอบ ผู้ใช้สามารถกดเก็บกราฟไว้รันซ้ำภายหลังได้",
          schema: { type: "object",
                    properties: { title: { type: "string" }, kind: { type: "string", enum: CHART_KINDS }, query: query_schema,
                                  x: { type: "string" }, y: { type: "array", items: { type: "string" } }, series_by: { type: "string" } },
                    required: %w[title kind query] } },
        { name: "list_imported_datasets", description: "รายการชุดข้อมูลที่ อบต. นำเข้าเอง (ประชากร ทรัพยากร บุคลากร ฯลฯ) ที่บัญชีนี้เข้าถึงได้", schema: { type: "object", properties: {} } },
        { name: "describe_source", description: "ดูรายการฟิลด์ของแหล่งข้อมูล โดยเฉพาะชุดข้อมูลนำเข้า dataset:<id>",
          schema: { type: "object", properties: { source: { type: "string" } }, required: %w[source] } }
      ]
    end
  end
end

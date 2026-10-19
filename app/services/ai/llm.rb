module Ai
  # Provider adapters for the assistant. Both speak in their provider's own message format so a conversation's
  # history can be replayed exactly (append-only); Ai::Agent only sees the small Response struct.
  module Llm
    class Error < StandardError; end

    ToolCall = Struct.new(:id, :name, :input, keyword_init: true)
    Response = Struct.new(:text, :tool_calls, :stop_reason, :assistant_message, :usage, :model, keyword_init: true)

    def self.for(provider)
      raise Error, "ยังไม่ได้ตั้งค่า LLM — ติดต่อผู้ดูแลระบบให้เพิ่มผู้ให้บริการ AI ในหน้าตั้งค่าระบบ" unless provider

      provider.anthropic? ? Anthropic.new(provider) : OpenaiCompatible.new(provider)
    end

    # Claude through the official Anthropic SDK. Thinking stays on (adaptive) and depth is set with effort.
    class Anthropic
      FALLBACK_MODELS = %w[claude-fable-5-1 claude-opus-5-5 claude-opus-5 claude-sonnet-5-5].freeze
      TIMEOUT = 180

      def initialize(provider)
        @provider = provider
      end

      def format = "anthropic"

      def chat(system:, tools:, messages:)
        params = {
          model: @provider.model, max_tokens: @provider.max_tokens,
          system_: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
          messages: messages.map { |message| message.deep_symbolize_keys }
        }
        params[:tools] = tools.map { |tool| { name: tool[:name], description: tool[:description], input_schema: tool[:schema] } } if tools.any?
        params[:output_config] = { effort: @provider.effort.to_sym } if @provider.effort.present?
        # Server-side fallback reroutes a refused request instead of failing the turn (Claude API only).
        if @provider.base_url.blank? && FALLBACK_MODELS.include?(@provider.model)
          params[:betas] = ["server-side-fallback-2026-07-01"]
          params[:fallbacks] = :default
        end

        message = client.beta.messages.create(**params)
        blocks = message.content.map { |block| JSON.parse(block.to_json) }
        if message.stop_reason == :refusal
          raise Error, "AI ปฏิเสธคำขอนี้#{" (#{message.stop_details.category})" if message.stop_details&.category} — ลองถามใหม่ด้วยถ้อยคำอื่น"
        end

        Response.new(
          text: blocks.select { |block| block["type"] == "text" }.map { |block| block["text"] }.join("\n").strip,
          tool_calls: blocks.select { |block| block["type"] == "tool_use" }.map { |block| ToolCall.new(id: block["id"], name: block["name"], input: block["input"] || {}) },
          stop_reason: message.stop_reason.to_s, assistant_message: { "role" => "assistant", "content" => blocks },
          usage: { "input" => message.usage.input_tokens, "output" => message.usage.output_tokens,
                   "cache_read" => message.usage.cache_read_input_tokens }.compact,
          model: message.model.to_s
        )
      rescue ::Anthropic::Errors::AuthenticationError
        raise Error, "API key ของ Claude ไม่ถูกต้อง — แจ้งผู้ดูแลระบบให้ตรวจสอบในหน้าตั้งค่า AI"
      rescue ::Anthropic::Errors::NotFoundError
        raise Error, "ไม่พบโมเดล #{@provider.model} — แจ้งผู้ดูแลระบบให้ตรวจสอบชื่อโมเดล"
      rescue ::Anthropic::Errors::RateLimitError
        raise Error, "มีการใช้งาน AI มากเกินโควตาชั่วคราว กรุณาลองใหม่อีกครั้งในอีกสักครู่"
      rescue ::Anthropic::Errors::APIConnectionError, ::Anthropic::Errors::APITimeoutError
        raise Error, "เชื่อมต่อบริการ AI ไม่ได้หรือใช้เวลานานเกินไป กรุณาลองใหม่"
      rescue ::Anthropic::Errors::APIStatusError => error
        raise Error, "บริการ AI ตอบกลับผิดพลาด (#{error.status}): #{error.message.to_s.truncate(200)}"
      end

      def user_message(text) = { "role" => "user", "content" => text }
      def assistant_text(text) = { "role" => "assistant", "content" => text }

      # All results of one round go back in a single user message, so the model keeps making parallel calls.
      def tool_results(results)
        [{ "role" => "user", "content" => results.map do |result|
          { "type" => "tool_result", "tool_use_id" => result[:id], "content" => result[:content], "is_error" => result[:error] }.compact
        end }]
      end

      def test!
        client.models.retrieve(@provider.model)
        "เชื่อมต่อสำเร็จ — พบโมเดล #{@provider.model}"
      rescue ::Anthropic::Errors::APIError => error
        raise Error, "ทดสอบไม่ผ่าน: #{error.message.to_s.truncate(200)}"
      end

      private

      def client
        @client ||= ::Anthropic::Client.new(api_key: @provider.api_key.presence || ENV["ANTHROPIC_API_KEY"],
                                            base_url: @provider.base_url.presence, timeout: TIMEOUT, max_retries: 2)
      end
    end

    # OpenAI Chat Completions format, which local and self-hosted servers (Ollama, vLLM, LM Studio, Typhoon,
    # OpenRouter) also expose. The model must support function calling to query data.
    class OpenaiCompatible
      TIMEOUT = 180

      def initialize(provider)
        @provider = provider
      end

      def format = "openai"

      def chat(system:, tools:, messages:)
        body = { model: @provider.model, max_tokens: @provider.max_tokens, temperature: 0.2,
                 messages: [{ role: "system", content: system }] + messages }
        if tools.any?
          body[:tools] = tools.map { |tool| { type: "function", function: { name: tool[:name], description: tool[:description], parameters: tool[:schema] } } }
          body[:tool_choice] = "auto"
        end
        data = begin
          stream_chat(body)
        rescue Error => error
          # Newer models (Claude 5, OpenAI reasoning models) reject sampling parameters; retry once without them.
          raise unless error.message.include?("temperature")

          stream_chat(body.except(:temperature))
        end
        choice = Array(data["choices"]).first or raise Error, "บริการ AI ไม่ได้ส่งคำตอบกลับมา"
        message = choice["message"].to_h.slice("role", "content", "tool_calls")
        message["role"] = "assistant"
        calls = Array(message["tool_calls"]).map do |call|
          input = JSON.parse(call.dig("function", "arguments").presence || "{}") rescue { "_invalid_json" => call.dig("function", "arguments") }
          ToolCall.new(id: call["id"], name: call.dig("function", "name"), input: input)
        end
        Response.new(text: strip_thinking(message["content"].to_s), tool_calls: calls, stop_reason: choice["finish_reason"].to_s,
                     assistant_message: message, usage: data["usage"].to_h.slice("prompt_tokens", "completion_tokens"), model: data["model"] || @provider.model)
      end

      def user_message(text) = { "role" => "user", "content" => text }
      def assistant_text(text) = { "role" => "assistant", "content" => text }

      def tool_results(results)
        results.map { |result| { "role" => "tool", "tool_call_id" => result[:id], "content" => result[:content] } }
      end

      def test!
        data = get("models")
        ids = Array(data["data"]).map { |model| model["id"] }
        return "เชื่อมต่อสำเร็จ — พบโมเดล #{@provider.model}" if ids.include?(@provider.model)

        "เชื่อมต่อสำเร็จ แต่ไม่พบโมเดล #{@provider.model} ในรายการ (#{ids.first(8).join(', ')})"
      end

      private

      def strip_thinking(text) = text.gsub(%r{<think>.*?</think>}m, "").strip

      # Streams the completion so bytes keep flowing: proxies such as Cloudflare cut a request that sends
      # nothing for 100 seconds (HTTP 524), which slow self-hosted models easily exceed. The deltas are folded
      # back into a normal completion; servers that ignore `stream` reply with plain JSON, handled by `request`.
      def stream_chat(body)
        req = Net::HTTP::Post.new(uri("chat/completions"))
        req.body = body.merge(stream: true, stream_options: { include_usage: true }).to_json
        req["Content-Type"] = "application/json"
        req["Accept"] = "text/event-stream, application/json"
        req["Authorization"] = "Bearer #{@provider.api_key}" if @provider.api_key.present?
        Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: req.uri.scheme == "https", open_timeout: 10, read_timeout: TIMEOUT) do |http|
          http.request(req) do |response|
            return read_stream(response) if response.is_a?(Net::HTTPSuccess) && response["content-type"].to_s.include?("event-stream")

            return parse_response(response, response.read_body)
          end
        end
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
        raise Error, "เชื่อมต่อบริการ AI ไม่ได้: #{error.message.truncate(120)}"
      end

      def read_stream(response)
        content = +""
        calls = {}
        finish_reason = model = nil
        usage = {}
        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (line_end = buffer.index("\n"))
            line = buffer.slice!(0..line_end).strip
            next unless line.start_with?("data:")

            payload = line.delete_prefix("data:").strip
            next if payload.empty? || payload == "[DONE]"

            event = JSON.parse(payload) rescue next
            raise Error, "บริการ AI ตอบกลับผิดพลาด: #{(event.dig('error', 'message') || event['error']).to_s.truncate(200)}" if event["error"]

            model ||= event["model"]
            usage = event["usage"] if event["usage"].is_a?(Hash)
            choice = Array(event["choices"]).first or next
            finish_reason = choice["finish_reason"] if choice["finish_reason"]
            delta = choice["delta"].to_h
            content << delta["content"].to_s
            Array(delta["tool_calls"]).each do |part|
              call = calls[part["index"] || calls.size] ||= { "id" => nil, "type" => "function", "function" => { "name" => +"", "arguments" => +"" } }
              call["id"] ||= part["id"]
              call["function"]["name"] << part.dig("function", "name").to_s
              call["function"]["arguments"] << part.dig("function", "arguments").to_s
            end
          end
        end
        message = { "role" => "assistant", "content" => content }
        message["tool_calls"] = calls.sort.map(&:last) if calls.any?
        { "choices" => [{ "message" => message, "finish_reason" => finish_reason }], "usage" => usage, "model" => model }
      end

      def post(path, body) = request(Net::HTTP::Post.new(uri(path)).tap { |req| req.body = body.to_json })
      def get(path) = request(Net::HTTP::Get.new(uri(path)))

      def uri(path) = URI.parse("#{@provider.base_url}/#{path}")

      def request(req)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@provider.api_key}" if @provider.api_key.present?
        response = Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: req.uri.scheme == "https", open_timeout: 10, read_timeout: TIMEOUT) do |http|
          http.request(req)
        end
        parse_response(response, response.body)
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
        raise Error, "เชื่อมต่อบริการ AI ไม่ได้: #{error.message.truncate(120)}"
      end

      def parse_response(response, body)
        data = JSON.parse(body.presence || "{}")
        return data if response.is_a?(Net::HTTPSuccess)

        raise Error, "บริการ AI ตอบกลับผิดพลาด (#{response.code}): #{(data.dig('error', 'message') || data['error'] || body).to_s.truncate(200)}"
      rescue JSON::ParserError
        # Gateways (e.g. Cloudflare 502/504/524) answer with HTML when the model server is down or too slow.
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "เซิร์ฟเวอร์ AI ไม่ตอบสนอง (HTTP #{response.code}) — เซิร์ฟเวอร์อาจล่มหรือทำงานช้าเกินไป กรุณาลองใหม่ภายหลัง"
        end
        raise Error, "บริการ AI ตอบกลับในรูปแบบที่อ่านไม่ได้ — ตรวจสอบ Base URL (มักลงท้ายด้วย /v1)"
      end
    end
  end
end

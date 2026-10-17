require "net/http"
require "base64"

module Tts
  # Turns a Thai script into one MP3 using a TtsProvider. Long scripts are split at sentence/space boundaries to
  # stay under each API's request limit, and the MP3 chunks are concatenated (MP3 frames play back-to-back).
  class Synthesizer
    class Error < StandardError; end

    Result = Struct.new(:audio, :content_type, :provider, :voice, :characters, keyword_init: true)
    CHUNK_LIMITS = { "google" => 400, "botnoi" => 900, "openai" => 3500 }.freeze
    # Self-hosted OpenAI-compatible servers (Open WebUI, llama-swap) render slowly and sit behind proxies that cut
    # requests at ~100 s, so they get short chunks: each one is a quick request that can be retried on its own.
    SELF_HOSTED_CHUNK_LIMIT = 400
    TIMEOUT = 120
    ATTEMPTS = 3
    class RetryableError < Error; end

    def self.call(text, provider: TtsProvider.default, voice: nil) = new(provider, voice).call(text)

    def initialize(provider, voice = nil)
      raise Error, "ยังไม่ได้ตั้งค่าบริการสร้างเสียง — ผู้ดูแลระบบเพิ่มได้ที่ ตั้งค่าระบบ › ผู้ให้บริการเสียง" unless provider
      raise Error, "ยังไม่ได้ใส่ API key ของ #{provider.name}" if provider.api_key.blank?

      @provider = provider
      @voice = voice.presence || provider.voice
    end

    def call(text)
      text = text.to_s.gsub(/[ \t]+/, " ").strip
      raise Error, "ไม่มีข้อความสำหรับสร้างเสียง" if text.blank?

      text = google_sentences(text) if @provider.kind == "google"

      audio = chunks(text).map { |chunk| with_retries { synthesize(chunk) } }.join.b
      Result.new(audio:, content_type: "audio/mpeg", provider: @provider.name, voice: @voice, characters: text.length)
    end

    private

    def chunks(text)
      limit = @provider.kind == "openai" && @provider.base_url.present? ? SELF_HOSTED_CHUNK_LIMIT : CHUNK_LIMITS.fetch(@provider.kind, 1000)
      # Thai has no sentence punctuation by default, so split on line breaks and spaces as well.
      pieces = text.split(/(?<=[\n。.!?ฯ])\s+|\s{2,}|\n+/).flat_map { |piece| piece.length > limit ? piece.split(" ").flat_map { |word| word.length > limit ? word.scan(/.{1,#{limit}}/m) : [word] } : [piece] }
      pieces.each_with_object([+""]) do |piece, list|
        piece = piece.strip
        next if piece.empty?

        if (list.last.length + piece.length + 1) > limit && list.last.present?
          list << piece.dup
        else
          list.last << (list.last.empty? ? piece : " #{piece}")
        end
      end.reject(&:empty?)
    end

    def with_retries
      attempt = 0
      begin
        attempt += 1
        yield
      rescue RetryableError => error
        raise Error, error.message if attempt >= ATTEMPTS

        sleep(2 * attempt)
        retry
      end
    end

    def synthesize(chunk)
      case @provider.kind
      when "google" then google(chunk)
      when "botnoi" then botnoi(chunk)
      when "openai" then openai(chunk)
      else raise Error, "ไม่รู้จักผู้ให้บริการเสียง #{@provider.kind}"
      end
    end

    def google(chunk)
      body = {
        input: { text: chunk },
        voice: { languageCode: @voice.to_s[/\A[a-z]{2}-[A-Z]{2}/] || "th-TH", name: @voice },
        audioConfig: { audioEncoding: "MP3", speakingRate: @provider.speaking_rate }
      }
      url = "#{@provider.effective_base_url}/v1/text:synthesize"
      response, json =
        if GoogleServiceAccount.json?(@provider.api_key)
          post(url, body.to_json, "Authorization" => "Bearer #{GoogleServiceAccount.access_token(@provider.api_key)}")
        else
          post("#{url}?key=#{CGI.escape(@provider.api_key)}", body.to_json)
        end
      unless response.is_a?(Net::HTTPSuccess) && json&.dig("audioContent")
        message = json&.dig("error", "message") || "HTTP #{response.code}"
        if message.include?("API keys are not supported")
          message = "API key นี้ใช้กับ Text-to-Speech ไม่ได้ (key ที่ขึ้นต้นด้วย AQ. ผูกกับ service account) — ใช้ API key ที่ขึ้นต้นด้วย AIza หรือวางไฟล์ service account JSON แทน"
        end
        raise(response.code.to_i >= 500 ? RetryableError : Error, "Google TTS: #{message}")
      end

      Base64.decode64(json["audioContent"])
    end

    # Google rejects over-long sentences, but Thai has no sentence-ending punctuation, so a whole paragraph counts
    # as one sentence. Group the space-separated phrases (Thai pauses) into short sentences ending with a period;
    # done before chunking so the chunker can split on those periods.
    GOOGLE_SENTENCE_LIMIT = 120

    def google_sentences(text)
      text.split(/\n+/).flat_map do |paragraph|
        paragraph.split(/\s+/).reject(&:empty?).each_with_object([+""]) do |phrase, sentences|
          particle = phrase.match?(/\A(นะ)?(ครับ|ค่ะ|คะ|จ้ะ|จ้า)\z/)
          sentences << +"" if sentences.last.present? && !particle && sentences.last.length + phrase.length + 1 > GOOGLE_SENTENCE_LIMIT
          sentences.last << (sentences.last.empty? ? phrase : " #{phrase}")
          # A polite particle closes a spoken sentence; break there once the sentence has some length.
          sentences << +"" if sentences.last.length >= 40 && phrase.match?(/(ครับ|ค่ะ|คะ|นะคะ|จ้ะ|จ้า)\z/)
        end
      end.reject(&:empty?).map { |sentence| sentence.match?(/[.!?ฯ]\z/) ? sentence : "#{sentence}." }.join(" ")
    end

    # Botnoi returns a link to the generated file, which is then downloaded.
    def botnoi(chunk)
      body = { text: chunk, speaker: @voice.to_s, volume: 1, speed: @provider.speaking_rate, type_media: "mp3", save_file: "true", language: "th" }
      response, json = post("#{@provider.effective_base_url}/openapi/v1/generate_audio", body.to_json, "Botnoi-Token" => @provider.api_key)
      url = json&.dig("audio_url") || json&.dig("data", "audio_url")
      raise Error, "Botnoi: #{json&.dig('message') || json&.dig('detail') || "HTTP #{response.code}"}" unless response.is_a?(Net::HTTPSuccess) && url.present?

      download(url)
    end

    def openai(chunk)
      body = { model: @provider.model || "gpt-4o-mini-tts", voice: @voice, input: chunk, response_format: "mp3", speed: @provider.speaking_rate,
               instructions: "อ่านเป็นภาษาไทยด้วยน้ำเสียงผู้ประกาศข่าวเสียงตามสายของหมู่บ้าน ชัดเจน เป็นกันเอง ไม่เร่งรีบ" }
      # Accept both "https://api.openai.com" and gateway URLs that already end in /v1 (Open WebUI: .../api/v1).
      base = @provider.effective_base_url
      base = "#{base}/v1" unless base.end_with?("/v1")
      response, json = post("#{base}/audio/speech", body.to_json, "Authorization" => "Bearer #{@provider.api_key}")
      unless response.is_a?(Net::HTTPSuccess) && json.nil?
        message = "OpenAI TTS: #{json&.dig('error', 'message') || json&.dig('detail') || "HTTP #{response.code}"}"
        raise(response.code.to_i >= 500 || response.code == "429" ? RetryableError : Error, message)
      end

      response.body
    end

    def post(url, body, headers = {})
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      headers.each { |key, value| request[key] = value }
      request.body = body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: TIMEOUT) { |http| http.request(request) }
      json = response.content_type.to_s.include?("json") ? (JSON.parse(response.body) rescue nil) : nil
      [response, json]
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
      raise RetryableError, "เชื่อมต่อบริการเสียงไม่ได้: #{error.message.truncate(120)}"
    end

    def download(url)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri) }
      raise Error, "ดาวน์โหลดไฟล์เสียงไม่สำเร็จ (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end

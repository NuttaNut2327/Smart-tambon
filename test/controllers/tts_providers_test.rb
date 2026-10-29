require "test_helper"
require "minitest/mock"

# Text-to-speech providers: central vs per-อบต. scoping, and the ElevenLabs Thai request.
class TtsProvidersTest < ActionDispatch::IntegrationTest
  VOICE = "abcVoiceThai01".freeze

  # Stands in for Net::HTTP: records each request and answers with a canned response.
  class FakeHttp
    attr_reader :requests

    def initialize(code: "200", body: "ID3mp3", content_type: "audio/mpeg")
      @code, @body, @content_type = code, body, content_type
      @requests = []
    end

    def start(host, _port, **)
      yield(self).tap { @host = host }
    end

    def request(request)
      @requests << request
      klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(@code)
      klass.new("1.1", @code, "").tap do |response|
        response["Content-Type"] = @content_type
        response.instance_variable_set(:@body, @body)
        response.instance_variable_set(:@read, true)
      end
    end
  end

  setup do
    @province = Province.create!(code: "A97", name_th: "จังหวัดทดสอบเสียง")
    @first = create_subdistrict("A9701", "ตำบลเสียงหนึ่ง", 100.0)
    @second = create_subdistrict("A9702", "ตำบลเสียงสอง", 101.0)
    @admin = User.create!(username: "tts_admin_one", password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
    @other = User.create!(username: "tts_admin_two", password: "Password123!", role: :subdistrict_admin, subdistrict: @second)
    @central = create_provider(name: "Google กลาง", kind: "google", voice: "th-TH-Standard-A", is_default: true, key: "AIzaCentral")
  end

  teardown do
    TtsProvider.delete_all
    BroadcastProgram.where(:organization_key.in => [@admin&.organization_key, @other&.organization_key].compact).delete_all
    [@admin, @other].compact.each(&:destroy)
    @province&.subdistricts&.destroy_all
    @province&.destroy
  end

  test "an อบต. admin adds its own ElevenLabs account, seen only by that อบต." do
    sign_in @admin
    get new_tts_provider_path(kind: "elevenlabs")
    assert_response :success
    assert_includes response.body, "เสียงอ่านข่าวของ อบต."
    post tts_providers_path, params: { tts_provider: { name: "ElevenLabs ของ อบต.", kind: "elevenlabs", voice: VOICE, model: "eleven_v3",
                                                       speaking_rate: "1.0", enabled: "1", is_default: "1", api_key: "sk_test_org",
                                                       base_url: "http://169.254.169.254" } }
    assert_redirected_to tts_providers_path

    provider = TtsProvider.find_by(name: "ElevenLabs ของ อบต.")
    assert_equal @admin.organization_key, provider.organization_key
    assert_nil provider.base_url, "an อบต. must not set a custom endpoint"
    assert_equal "sk_test_org", provider.api_key
    assert @central.reload.is_default?, "an อบต. default must not clear the central default"

    get edit_tts_provider_path(provider)
    assert_response :success
    assert_includes response.body, "โหลดเสียงจากบัญชี ElevenLabs"
    assert_includes response.body, "eleven_v3"
    assert_not_includes response.body, "tts_provider[base_url]"

    get tts_providers_path
    assert_response :success
    assert_includes response.body, "ElevenLabs ของ อบต."
    assert_includes response.body, "Google กลาง"

    sign_in @other
    get tts_providers_path
    assert_not_includes response.body, "ElevenLabs ของ อบต."
    get edit_tts_provider_path(provider)
    assert_redirected_to tts_providers_path
  end

  test "an อบต. cannot edit the central provider" do
    sign_in @admin
    patch tts_provider_path(@central), params: { tts_provider: { name: "ยึด" } }
    assert_redirected_to tts_providers_path
    assert_equal "Google กลาง", @central.reload.name
  end

  test "ElevenLabs rejects models that cannot read Thai" do
    provider = TtsProvider.new(name: "x", kind: "elevenlabs", voice: VOICE, model: "eleven_multilingual_v2", organization_key: @admin.organization_key)
    assert_not provider.valid?
    assert provider.errors[:model].any?
    assert_equal "eleven_v3", TtsProvider.new(name: "y", kind: "elevenlabs").tap(&:valid?).model
  end

  test "broadcast programs use the อบต.'s own provider before the central default" do
    own = create_provider(name: "11L", kind: "elevenlabs", voice: VOICE, organization_key: @admin.organization_key, key: "sk")
    foreign = create_provider(name: "11L อื่น", kind: "elevenlabs", voice: VOICE, organization_key: @other.organization_key, key: "sk")

    program = BroadcastProgram.new(organization_key: @admin.organization_key, name: "ข่าวเช้า")
    assert_equal own, program.tts_provider
    program.tts_provider_id = foreign.id
    assert_equal own, program.tts_provider, "another อบต.'s provider is never used"
    program.tts_provider_id = @central.id
    assert_equal @central, program.tts_provider
    assert_equal @central, BroadcastProgram.new(organization_key: @other.organization_key.succ).tts_provider
  end

  test "ElevenLabs synthesis sends Thai text to the chosen voice with language th" do
    provider = create_provider(name: "11L", kind: "elevenlabs", voice: VOICE, speaking_rate: 1.5, organization_key: @admin.organization_key, key: "sk_live")
    http = FakeHttp.new

    result = Net::HTTP.stub(:start, http.method(:start)) { Tts::Synthesizer.call("สวัสดีครับ ทดสอบเสียงภาษาไทย", provider:) }

    request = http.requests.sole
    assert_equal "/v1/text-to-speech/#{VOICE}?output_format=mp3_44100_128", request.path
    assert_equal "sk_live", request["xi-api-key"]
    body = JSON.parse(request.body)
    assert_equal "th", body["language_code"]
    assert_equal "eleven_v3", body["model_id"]
    assert_equal 1.2, body.dig("voice_settings", "speed"), "speed is clamped to what ElevenLabs accepts"
    assert_equal "ID3mp3", result.audio
  end

  test "ElevenLabs errors come back in Thai" do
    provider = create_provider(name: "11L", kind: "elevenlabs", voice: VOICE, organization_key: @admin.organization_key, key: "bad")
    http = FakeHttp.new(code: "401", body: { detail: { status: "invalid_api_key", message: "Invalid API key" } }.to_json, content_type: "application/json")

    error = assert_raises(Tts::Synthesizer::Error) { Net::HTTP.stub(:start, http.method(:start)) { Tts::Synthesizer.call("ทดสอบ", provider:) } }
    assert_includes error.message, "API key ไม่ถูกต้อง"
  end

  test "the voices endpoint lists the account's ElevenLabs voices" do
    sign_in @admin
    provider = create_provider(name: "11L", kind: "elevenlabs", voice: VOICE, organization_key: @admin.organization_key, key: "sk")
    payload = { voices: [{ voice_id: "th1", name: "นักข่าวไทย", category: "professional", labels: { gender: "female", language: "th" } }] }
    http = FakeHttp.new(body: payload.to_json, content_type: "application/json")

    Net::HTTP.stub(:start, http.method(:start)) { get voices_tts_provider_path(provider), as: :json }

    assert_response :success
    voice = response.parsed_body["voices"].sole
    assert_equal "th1", voice["id"]
    assert_equal "female · th", voice["labels"]
  end

  private

  def create_provider(key:, **attributes) = TtsProvider.new(attributes).tap { |provider| provider.assign_api_key(key) }.tap(&:save!)

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end

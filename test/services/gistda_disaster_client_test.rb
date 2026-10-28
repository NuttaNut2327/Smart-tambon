require "test_helper"

class GistdaDisasterClientTest < ActiveSupport::TestCase
  # Stands in for Net::HTTP: records the request and answers with a canned response.
  class FakeHttp
    attr_reader :requests

    def initialize(code: "200", body: "{}", content_type: "application/json")
      @code, @body, @content_type = code, body, content_type
      @requests = []
    end

    def start(_host, _port, **_options)
      yield self
    end

    def request(req)
      @requests << req
      klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(@code)
      response = klass.new("1.1", @code, "")
      response["Content-Type"] = @content_type
      response.instance_variable_set(:@body, @body)
      response.instance_variable_set(:@read, true)
      response
    end
  end

  setup do
    @province = Province.create!(code: "G98", name_th: "จังหวัดทดสอบ GISTDA")
    @subdistrict = @province.subdistricts.create!(code: "G9801", name_th: "ตำบลทดสอบ GISTDA")
    @user = User.create!(username: "gistda_client_user", email: "gistda_client_user@example.test", password: "Password123!",
      role: :subdistrict_admin, subdistrict: @subdistrict)
    @system = SystemSetting.current
    @original_system_key = @system.gistda_api_key_ciphertext
  end

  teardown do
    OrganizationSetting.where(organization_key: @user.organization_key).delete_all
    @system.set(gistda_api_key_ciphertext: @original_system_key)
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "organization key takes precedence over the system key" do
    @system.assign_secret("gistda_api_key", "system-key")
    @system.save!
    assert_equal "system", GistdaDisasterClient.for(@user).key_source

    setting = OrganizationSetting.for(@user)
    setting.assign_gistda_api_key("org-key-1234")
    setting.save!
    client = GistdaDisasterClient.for(@user)
    assert_equal "organization", client.key_source

    http = FakeHttp.new(body: { type: "FeatureCollection", features: [] }.to_json)
    GistdaDisasterClient.new(api_key: "org-key-1234", key_source: "organization", base_url: "http://weather.test", admin_key: "admin", http:)
      .features("flood", period: 7, bbox: [100.0, 14.0, 100.1, 14.1])
    assert_equal "org-key-1234", http.requests.first["X-Gistda-Api-Key"]
  end

  test "organization key is stored encrypted and can be cleared" do
    setting = OrganizationSetting.for(@user)
    setting.assign_gistda_api_key("org-secret-abcd")
    setting.save!
    raw = OrganizationSetting.collection.find(organization_key: @user.organization_key).first
    refute_includes raw.to_json, "org-secret-abcd"
    assert_equal "••••••abcd", setting.reload.masked_gistda_api_key

    setting.assign_gistda_api_key("", clear: false)
    assert_equal "org-secret-abcd", setting.gistda_api_key, "blank input keeps the current key"
    setting.assign_gistda_api_key(nil, clear: true)
    assert_nil setting.gistda_api_key
  end

  test "posts the area query to the weather service with the admin key" do
    http = FakeHttp.new(body: { type: "FeatureCollection", count: 1, features: [{ type: "Feature" }] }.to_json)
    client = GistdaDisasterClient.new(api_key: "k", base_url: "http://weather.test", admin_key: "admin", http:)
    payload = client.features("hotspots", period: 3, bbox: [100.0, 14.0, 100.1, 14.1], boundary_wkt: "POLYGON((0 0,1 0,1 1,0 0))")

    request = http.requests.first
    assert_equal "/api/v1/gistda/features", request.path
    assert_equal "admin", request["X-API-Key"]
    assert_equal({ "dataset" => "hotspots", "period_days" => 3, "bbox" => [100.0, 14.0, 100.1, 14.1],
                   "boundary_wkt" => "POLYGON((0 0,1 0,1 1,0 0))" }, JSON.parse(request.body))
    assert_equal 1, payload["count"]
  end

  test "maps weather service errors" do
    missing = FakeHttp.new(code: "503", body: { detail: { code: "gistda_key_missing" } }.to_json)
    assert_raises(GistdaDisasterClient::MissingKey) do
      GistdaDisasterClient.new(api_key: nil, base_url: "http://weather.test", admin_key: "admin", http: missing).features("flood", period: 7, bbox: [1, 2, 3, 4])
    end
    rejected = FakeHttp.new(code: "502", body: { detail: { code: "gistda_key_rejected" } }.to_json)
    error = assert_raises(GistdaDisasterClient::Error) do
      GistdaDisasterClient.new(api_key: "bad", base_url: "http://weather.test", admin_key: "admin", http: rejected).features("flood", period: 7, bbox: [1, 2, 3, 4])
    end
    assert_match "ปฏิเสธ", error.message
  end

  test "tile returns png bytes or nil for empty tiles" do
    png = FakeHttp.new(body: "\x89PNG".b, content_type: "image/png")
    client = GistdaDisasterClient.new(api_key: "k", base_url: "http://weather.test", admin_key: "admin", http: png)
    assert_equal ["\x89PNG".b, "image/png"], client.tile("drought", z: 6, x: 50, y: 29)
    assert_equal "/api/v1/gistda/tiles/drought/6/50/29?period_days=7", png.requests.first.path

    empty = FakeHttp.new(code: "204", body: "")
    assert_nil GistdaDisasterClient.new(api_key: "k", base_url: "http://weather.test", admin_key: "admin", http: empty).tile("flood", z: 6, x: 1, y: 1)
  end
end

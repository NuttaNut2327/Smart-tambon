require "test_helper"
require "minitest/mock"

class GistdaApiTest < ActionDispatch::IntegrationTest
  class FakeClient
    attr_reader :calls, :tiles

    def initialize(key_source: "system", error: nil)
      @key_source, @error = key_source, error
      @calls = []
      @tiles = []
    end

    attr_reader :key_source

    def features(dataset, period:, bbox:, boundary_wkt: nil)
      raise @error if @error

      @calls << { dataset:, period:, bbox:, boundary_wkt: }
      { "type" => "FeatureCollection", "dataset" => dataset, "period_days" => period, "count" => 1, "truncated" => false,
        "fetched_at" => "2026-10-23T15:00:00+00:00",
        "features" => [{ "type" => "Feature", "id" => "a", "geometry" => { "type" => "Point", "coordinates" => [100.05, 14.05] },
                         "properties" => { "kind" => "hotspot", "frp" => nil } }] }
    end

    def tile(layer, z:, x:, y:, period:)
      @tiles << [layer, z, x, y, period]
      ["\x89PNG".b, "image/png"]
    end
  end

  setup do
    @province = Province.create!(code: "G97", name_th: "จังหวัดทดสอบแผนที่ GISTDA")
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    ring = [[100.0, 14.0], [100.1, 14.0], [100.1, 14.1], [100.0, 14.1], [100.0, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    @subdistrict = @province.subdistricts.create!(code: "G9701", name_th: "ตำบลทดสอบแผนที่",
      boundary: factory.multi_polygon([factory.polygon(factory.linear_ring(ring))]))
    @user = User.create!(username: "gistda_map_user", email: "gistda_map_user@example.test", password: "Password123!",
      role: :subdistrict_user, subdistrict: @subdistrict)
    sign_in @user
  end

  teardown do
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "requires sign in" do
    sign_out @user
    get api_gistda_path("flood")
    assert_response :redirect
  end

  test "queries the boundary envelope and asks the weather service to clip to the boundary" do
    client = FakeClient.new
    GistdaDisasterClient.stub(:for, client) { get api_gistda_path("flood"), params: { period: 3 } }

    assert_response :success
    call = client.calls.first
    assert_equal ["flood", 3], [call[:dataset], call[:period]]
    assert_equal [100.0, 14.0, 100.1, 14.1], call[:bbox]
    assert_match(/\AMULTIPOLYGON/, call[:boundary_wkt])
    body = response.parsed_body
    assert_equal "system", body["key_source"]
    assert_nil body.dig("features", 0, "properties", "frp"), "missing values stay null"
  end

  test "hotspots GISTDA tags with the user's tambon code are kept even just outside our boundary" do
    client = FakeClient.new
    def client.features(dataset, period:, bbox:, boundary_wkt: nil)
      @calls << { dataset:, period:, bbox:, boundary_wkt: }
      point = ->(id, lon, code) { { "type" => "Feature", "id" => id, "geometry" => { "type" => "Point", "coordinates" => [lon, 14.05] },
                                     "properties" => { "kind" => "hotspot", "tambon_code" => code } } }
      { "type" => "FeatureCollection", "count" => 3, "features" => [point.call("inside", 100.05, nil), point.call("edge", 100.11, "G9701"), point.call("other", 100.12, "999999")] }
    end
    GistdaDisasterClient.stub(:for, client) { get api_gistda_path("hotspots") }

    assert_equal %w[inside edge], response.parsed_body["features"].map { |feature| feature["id"] }
    call = client.calls.first
    assert_nil call[:boundary_wkt], "clipping happens in Rails so code matches survive"
    assert_equal [99.97, 13.97, 100.13, 14.13], call[:bbox]
  end

  test "a requested bbox is narrowed to the user's area and cannot widen it" do
    client = FakeClient.new
    GistdaDisasterClient.stub(:for, client) { get api_gistda_path("flood"), params: { period: 7, bbox: "99,13,100.05,14.05" } }
    assert_equal [100.0, 14.0, 100.05, 14.05], client.calls.first[:bbox]

    GistdaDisasterClient.stub(:for, client) { get api_gistda_path("flood"), params: { bbox: "101,15,102,16" } }
    assert_response :success
    assert_equal 0, response.parsed_body["count"], "bbox outside the area returns nothing"
    assert_equal 1, client.calls.size
  end

  test "unknown dataset and missing key" do
    get api_gistda_path("earthquake")
    assert_response :not_found

    GistdaDisasterClient.stub(:for, FakeClient.new(error: GistdaDisasterClient::MissingKey.new("x"))) { get api_gistda_path("flood") }
    assert_response :service_unavailable
    assert_equal "gistda_key_missing", response.parsed_body["code"]
  end

  test "tiles are served only inside the user's area" do
    client = FakeClient.new
    GistdaDisasterClient.stub(:for, client) do
      # z=10 tile containing 100.05E 14.05N
      get api_gistda_tile_path(layer: "drought", z: 10, x: 796, y: 471)
      assert_response :success
      assert_equal "image/png", response.media_type

      get api_gistda_tile_path(layer: "drought", z: 10, x: 10, y: 10)
      assert_response :no_content

      get api_gistda_tile_path(layer: "ndvi", z: 10, x: 796, y: 471)
      assert_response :not_found
    end
    assert_equal [["drought", 10, 796, 471, 1]], client.tiles
  end
end

require "test_helper"

class BroadcastsHazardOutlookTest < ActiveSupport::TestCase
  class FakeWeather
    attr_reader :days_requested

    def initialize(rain: [9.4, 40.0, 95.2, nil], fail: false)
      @rain, @fail = rain, fail
    end

    def admin? = false

    def nearest(lat:, lon:, max_km: nil)
      raise WeatherFeedClient::Error, "down" if @fail

      { "id" => 8, "name" => "Pa Klang", "name_th" => "ต.ป่ากลาง", "distance_km" => 0.56 }
    end

    def daily_forecast(_id, days:)
      @days_requested = days
      { "run" => { "model" => "ecmwf_ifs025", "run_init_time" => "2026-10-27T18:00:00Z" },
        "days" => @rain.each_with_index.map do |mm, lead|
          { "forecast_date" => (Date.new(2026, 10, 28) + lead).iso8601, "forecast_lead_days" => lead, "precipitation_sum_mm" => mm,
            "precipitation_probability_max_pct" => 100.0, "temperature_max_c" => 29.1, "temperature_min_c" => 22.4, "wind_gusts_max_kmh" => nil }
        end }
    end
  end

  class FakeGistda
    attr_reader :key_source

    def initialize(features: [], error: nil)
      @features, @error, @key_source = features, error, "organization"
    end

    def features(dataset, period:, bbox:, boundary_wkt: nil)
      raise @error if @error

      { "fetched_at" => "2026-10-28T07:00:00+00:00", "truncated" => false, "number_matched" => @features.size,
        "features" => @features.select { |feature| feature.dig("properties", "kind") == (dataset == "flood" ? "flood" : "hotspot") } }
    end
  end

  setup do
    @now = Time.zone.parse("2026-10-28 14:00 +07:00")
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    ring = [[100.88, 19.11], [100.95, 19.11], [100.95, 19.16], [100.88, 19.16], [100.88, 19.11]].map { |lon, lat| factory.point(lon, lat) }
    @province = Province.create!(code: "H98", name_th: "จังหวัดทดสอบข่าว")
    @subdistrict = @province.subdistricts.create!(code: "H9801", name_th: "ตำบลทดสอบข่าว", center: factory.point(100.92, 19.13),
      boundary: factory.multi_polygon([factory.polygon(factory.linear_ring(ring))]))
    @user = User.create!(username: "hazard_outlook_user", email: "hazard_outlook_user@example.test", password: "Password123!",
      role: :subdistrict_admin, subdistrict: @subdistrict)
  end

  teardown do
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "rain forecast for today and the next 3 days uses the TMD rain levels and lists heavy rain days" do
    weather = FakeWeather.new
    result = Broadcasts::HazardOutlook.new(@user, now: @now, weather_client: weather).weather_forecast

    assert_equal 4, weather.days_requested
    assert_equal ["ฝนเล็กน้อย", "ฝนหนัก", "ฝนหนักมาก"], result["days"].first(3).map { |day| day["rain_level"] }
    assert_equal %w[วันนี้ พรุ่งนี้ มะรืนนี้], result["days"].first(3).map { |day| day["when"] }
    assert_nil result["days"].last["rain_mm"], "missing forecast values stay nil"
    assert_nil result["days"].last["rain_level"]
    refute result["days"].first.key?("wind_gust_kmh")
    assert_equal [40.0, 95.2], result["heavy_rain_days"].map { |day| day["rain_mm"] }
    assert_equal "ต.ป่ากลาง", result["location"]
    assert_match "ecmwf_ifs025", result["source"]
  end

  test "weather outage is reported, not invented" do
    result = Broadcasts::HazardOutlook.new(@user, now: @now, weather_client: FakeWeather.new(fail: true)).weather_forecast
    assert_equal({ "error" => "ยังดึงพยากรณ์อากาศไม่ได้" }, result)
  end

  test "GISTDA hotspots: strict 24-hour count plus the latest pass, grouped by place" do
    hotspot = lambda do |at, village, code: "H9801", lon: 101.5|
      { "geometry" => { "type" => "Point", "coordinates" => [lon, 19.13] },
        "properties" => { "kind" => "hotspot", "acquired_at" => at, "village" => village, "tambon" => "ป่ากลาง", "tambon_code" => code,
                          "amphoe" => "ปัว", "province" => "น่าน", "land_use" => "เขต สปก." } }
    end
    gistda = FakeGistda.new(features: [hotspot.call("2026-10-28T05:05:00+00:00", "บ้านไร่รวงทอง"), hotspot.call("2026-10-28T06:10:00+00:00", "บ้านไร่รวงทอง"),
                                       hotspot.call("2026-10-27T06:00:00+00:00", "บ้านเก่า"), hotspot.call(nil, "ไม่ทราบเวลา"),
                                       hotspot.call("2026-10-28T06:10:00+00:00", "นอกพื้นที่", code: "999999"),
                                       hotspot.call("2026-10-28T06:20:00+00:00", "ในขอบเขต", code: nil, lon: 100.9)])
    result = Broadcasts::HazardOutlook.new(@user, now: @now, gistda_client: gistda).gistda_hotspots

    assert_equal 3, result["count_24h"]
    assert_equal 4, result["count_latest_day"], "points without a time or outside the area are left out"
    assert_equal "28 ต.ค. 2569 13:20 น.", result["latest_detection"]
    place = result["places"].first
    assert_equal ["บ้านไร่รวงทอง", "ต.ป่ากลาง", "อ.ปัว", "จ.น่าน", 2, 2], place.values_at("village", "tambon", "amphoe", "province", "count", "count_24h")
    assert_equal ["28 ต.ค. 2569 12:05 น.", "28 ต.ค. 2569 13:10 น."], place["detected"]
    assert_equal 0, result["places"].find { |item| item["village"] == "บ้านเก่า" }["count_24h"]
    assert_match "GISTDA", result["source"]
  end

  test "GISTDA flood areas are summed per tambon in rai and missing values stay nil" do
    flood = ->(sqm, rice) { { "properties" => { "kind" => "flood", "tambon" => "ต.ป่ากลาง", "amphoe" => "อ.ปัว", "area_sq_m" => sqm,
                                                "rice_area_sq_m" => rice, "population" => nil, "updated_at" => "2026-10-27T18:00:00Z" } } }
    result = Broadcasts::HazardOutlook.new(@user, now: @now, gistda_client: FakeGistda.new(features: [flood.call(16_000, nil), flood.call(8_000, nil)])).gistda_flood
    row = result["by_tambon"].sole
    assert_equal 2, result["flood_areas"]
    assert_equal 15.0, row["area_rai"]
    assert_nil row["rice_area_rai"]
    assert_nil row["population"]
  end

  test "GISTDA errors and programme data sources" do
    result = Broadcasts::HazardOutlook.new(@user, now: @now, gistda_client: FakeGistda.new(error: GistdaDisasterClient::MissingKey.new("x"))).gistda_flood
    assert_equal "ยังดึงข้อมูลพื้นที่น้ำท่วมจาก GISTDA ไม่ได้", result["error"]
    assert (%w[weather_forecast gistda_hotspots gistda_flood] - BroadcastProgram::DATA_SOURCES.keys).empty?
  end
end

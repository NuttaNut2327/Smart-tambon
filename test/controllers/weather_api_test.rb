require "test_helper"
require "minitest/mock"

class WeatherApiTest < ActionDispatch::IntegrationTest
  class FakeClient
    attr_reader :created, :synced

    LOCATIONS = [
      { "id" => 1, "code" => "nakhon-sawan", "name" => "Mueang Nakhon Sawan", "name_th" => "เมืองนครสวรรค์",
        "province" => "Nakhon Sawan", "latitude" => 15.7047, "longitude" => 100.1372, "timezone" => "Asia/Bangkok" }
    ].freeze

    def initialize(admin: false, near: nil, fail: false)
      @admin, @near, @fail = admin, near, fail
      @created = nil
      @synced = []
    end

    def admin? = @admin
    def locations = guard { LOCATIONS }
    def location(id) = guard { LOCATIONS.find { |l| l["id"] == id.to_i } }

    def nearest(lat:, lon:, max_km: nil)
      guard { max_km ? @near : LOCATIONS.first.merge("distance_km" => 215.4) }
    end

    def create_location(attrs)
      @created = attrs
      attrs.merge("id" => 99, "timezone" => "Asia/Bangkok")
    end

    def sync(job, location_ids:) = @synced << [job, location_ids]
    def current(_id) = { "current" => { "temperature_c" => 26.1, "uv_index" => nil } }

    def daily_forecast(_id, days:)
      { "run" => { "model" => "ecmwf_ifs025" },
        "days" => Array.new(days) { |i| { "forecast_date" => (Date.current + i).iso8601, "temperature_max_c" => 33.0 } } }
    end

    def hourly(_id, start:, finish:) = { "hours" => [{ "valid_time" => start.iso8601, "temperature_c" => 26.0 }] }

    def history(_id, start:, finish:)
      { "days" => [{ "temperature_max_c" => 32.0, "model" => "era5" }, { "temperature_max_c" => 33.0, "model" => "era5" }] }
    end

    private

    def guard
      raise WeatherFeedClient::Error, "down" if @fail

      yield
    end
  end

  setup do
    Rails.cache.clear
    @province = Province.create!(code: "W98", name_th: "จังหวัดทดสอบอากาศ")
    @subdistrict = Subdistrict.create!(province: @province, code: "W9801", name_th: "ตำบลทดสอบอากาศ",
      center: RGeo::Cartesian.preferred_factory(srid: 4326).point(99.5, 17.0))
    @user = User.create!(username: "weather_user", email: "weather_user@example.test", password: "Password123!",
      role: :subdistrict_admin, subdistrict: @subdistrict)
    sign_in @user
  end

  teardown do
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
    Rails.cache.clear
  end

  test "requires sign in" do
    sign_out @user
    get api_weather_path
    assert_response :redirect
  end

  test "returns panel payload for nearest location with distance when no admin key" do
    with_client(FakeClient.new) do
      get api_weather_path
    end
    assert_response :success
    body = response.parsed_body
    assert_equal "nakhon-sawan", body.dig("location", "code")
    assert_in_delta 215.4, body["distance_km"]
    assert_equal 7, body.dig("forecast", "days").size
    assert_nil body.dig("current", "uv_index"), "unavailable params stay null"
    assert_equal({ "average_c" => 32.5, "days" => 2, "source" => "era5" }, body["recent_high"])
    assert_equal [1], body["locations"].map { |l| l["id"] }
  end

  test "registers the user's subdistrict when no weather location is nearby and admin key is set" do
    client = FakeClient.new(admin: true)
    with_client(client) { get api_weather_path }
    assert_response :success
    assert_equal "tambon-w9801", client.created[:code]
    assert_in_delta 17.0, client.created[:latitude]
    assert_equal [["forecast", [99]], ["current", [99]], ["observation", [99]]], client.synced
    assert_equal 0.0, response.parsed_body["distance_km"]
  end

  test "explicit location id" do
    with_client(FakeClient.new) { get api_weather_path, params: { location_id: 1 } }
    assert_response :success
    assert_nil response.parsed_body["distance_km"]
  end

  test "service outage returns 503 with Thai message" do
    with_client(FakeClient.new(fail: true)) { get api_weather_path }
    assert_response :service_unavailable
    assert_match "สภาพอากาศ", response.parsed_body["error"]
  end

  private

  def with_client(client, &block)
    WeatherFeedClient.stub(:new, client, &block)
  end
end

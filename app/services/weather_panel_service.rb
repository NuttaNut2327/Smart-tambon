# Builds the dashboard weather panel payload from the weather service.
# Location: an explicit weather location id, else the weather location nearest the user's area. When no
# weather location lies within NEAR_KM and the admin key is configured, the user's subdistrict is registered
# with the weather service and synced once, so the panel shows that tambon instead of a far-away city.
class WeatherPanelService
  NEAR_KM = 10
  DEFAULT_LOCATION_CODE = "nakhon-sawan".freeze
  CACHE_TTL = 10.minutes

  def initialize(user:, global_viewer:, client: WeatherFeedClient.new)
    @user = user
    @global_viewer = global_viewer
    @client = client
  end

  def call(location_id: nil)
    location, distance_km = resolve_location(location_id)
    payload = Rails.cache.fetch(["weather_panel/v1", location["id"]], expires_in: CACHE_TTL) { build(location) }
    payload.merge("distance_km" => distance_km, "locations" => location_options)
  end

  # [weather location, distance_km] for the user's area (registers the subdistrict when nothing is near).
  def location = resolve_location(nil)

  private

  def resolve_location(location_id)
    return [@client.location(location_id), nil] if location_id.present?

    lon, lat = area_point
    if lat.nil?
      code = ENV["WEATHER_DEFAULT_LOCATION_CODE"].presence || DEFAULT_LOCATION_CODE
      all = @client.locations
      default = all.find { |loc| loc["code"] == code } || all.first
      raise WeatherFeedClient::Error, "no weather locations" unless default

      return [default, nil]
    end

    near = @client.nearest(lat:, lon:, max_km: NEAR_KM)
    return [near, near["distance_km"]] if near

    registered = register_subdistrict(lat, lon)
    return [registered, 0.0] if registered

    fallback = @client.nearest(lat:, lon:)
    raise WeatherFeedClient::Error, "no weather locations" unless fallback

    [fallback, fallback["distance_km"]]
  end

  def area_point
    subdistrict = @user.subdistrict
    return [subdistrict.center.x, subdistrict.center.y] if !@global_viewer && subdistrict&.center
    return nil if @global_viewer

    boundary = @user.access_boundary
    return nil unless boundary

    sql = ActiveRecord::Base.sanitize_sql_array([
      "SELECT ST_X(p), ST_Y(p) FROM (SELECT ST_PointOnSurface(ST_GeomFromText(?, 4326)) AS p) s", boundary.as_text
    ])
    ActiveRecord::Base.connection.select_rows(sql).first&.map(&:to_f)
  end

  def register_subdistrict(lat, lon)
    subdistrict = @user.subdistrict
    return nil unless @client.admin? && subdistrict

    location = @client.create_location(
      code: "tambon-#{subdistrict.code}".downcase,
      name: subdistrict.name_en.presence || subdistrict.name_th,
      name_th: "ต.#{subdistrict.name_th}",
      province: subdistrict.province&.name_th,
      district: subdistrict.district_name_th,
      subdistrict: subdistrict.name_th,
      latitude: lat.round(5),
      longitude: lon.round(5),
      timezone: "Asia/Bangkok"
    )
    %w[forecast current observation].each { |job| @client.sync(job, location_ids: [location["id"]]) }
    location
  rescue WeatherFeedClient::Error => e
    Rails.logger.warn("[weather] could not register #{subdistrict&.code}: #{e.message}")
    nil
  end

  def build(location)
    id = location["id"]
    now = Time.current
    today = now.in_time_zone(location["timezone"]).to_date
    history = @client.history(id, start: today - 10, finish: today - 1)["days"]
    observed_highs = history.filter_map { |day| day["temperature_max_c"] }
    {
      "location" => location,
      "current" => @client.current(id)["current"],
      "forecast" => @client.daily_forecast(id, days: 7),
      "hourly" => @client.hourly(id, start: now.beginning_of_hour, finish: now + 25.hours)["hours"],
      "recent_high" => observed_highs.any? ? {
        "average_c" => (observed_highs.sum / observed_highs.size).round(1),
        "days" => observed_highs.size,
        "source" => history.map { |day| day["model"] }.uniq.compact.join(", ")
      } : nil,
      "generated_at" => now.iso8601
    }
  end

  def location_options
    Rails.cache.fetch("weather_panel/locations", expires_in: CACHE_TTL) do
      @client.locations.map { |loc| loc.slice("id", "name", "name_th", "province") }
    end
  end
end

require "json"
require "net/http"

# Thin client for the standalone weather service (services/weather, FastAPI).
# Read endpoints are public; registering a location and triggering a sync need WEATHER_ADMIN_API_KEY.
class WeatherFeedClient
  class Error < StandardError; end

  DEFAULT_URL = "http://host.docker.internal:8010".freeze

  def initialize(base_url: ENV["WEATHER_API_URL"].presence || DEFAULT_URL, admin_key: ENV["WEATHER_ADMIN_API_KEY"],
                 http: nil)
    @base = URI(base_url)
    @admin_key = admin_key.presence
    @http = http
  end

  def admin?
    @admin_key.present?
  end

  def locations
    get("/api/v1/locations", limit: 500)
  end

  def nearest(lat:, lon:, max_km: nil)
    get("/api/v1/locations/nearest", { lat:, lon:, limit: 1, max_km: }.compact).first
  end

  def location(id)
    get("/api/v1/locations/#{id.to_i}")
  end

  def current(location_id)
    get("/api/v1/weather/current", location_id:)
  end

  def daily_forecast(location_id, days: 7)
    get("/api/v1/weather/forecast/daily", location_id:, days:)
  end

  def hourly(location_id, start:, finish:)
    get("/api/v1/weather/hourly", location_id:, start: start.utc.iso8601, end: finish.utc.iso8601)
  end

  def history(location_id, start:, finish:)
    get("/api/v1/weather/history/daily", location_id:, start: start.iso8601, end: finish.iso8601)
  end

  def create_location(attrs)
    request(Net::HTTP::Post, "/api/v1/locations", body: attrs, admin: true)
  end

  def sync(job, location_ids:)
    request(Net::HTTP::Post, "/api/v1/weather/sync", body: { job:, location_ids: }, admin: true, timeout: 60)
  end

  private

  def get(path, params = {})
    request(Net::HTTP::Get, path, params:)
  end

  def request(klass, path, params: {}, body: nil, admin: false, timeout: 8)
    raise Error, "WEATHER_ADMIN_API_KEY is not configured" if admin && !admin?

    uri = @base.dup
    uri.path = path
    uri.query = URI.encode_www_form(params) if params.present?
    req = klass.new(uri)
    req["Accept"] = "application/json"
    req["X-API-Key"] = @admin_key if admin
    if body
      req["Content-Type"] = "application/json"
      req.body = body.to_json
    end
    response = (@http || Net::HTTP).start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: 3, read_timeout: timeout) { |http| http.request(req) }
    raise Error, "weather service #{response.code} on #{path}: #{response.body.to_s.first(200)}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
    raise Error, "weather service unreachable (#{e.class}: #{e.message})"
  end
end

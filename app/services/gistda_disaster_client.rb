require "json"
require "net/http"

# GISTDA Disaster Open API data (flood polygons, VIIRS hotspots, drought/flood map tiles) read through the
# weather service (services/weather, /api/v1/gistda), which keeps them in its PostGIS database and only calls
# GISTDA when its cached copy has expired. The GISTDA key is resolved here — the อบต.'s own key first, then the
# system key (settings page, else GISTDA_API_KEY) — and sent per request; the weather service never stores it.
class GistdaDisasterClient
  class Error < StandardError; end
  class MissingKey < Error; end

  PERIODS = [1, 3, 7, 30].freeze
  TILE_LAYERS = %w[drought flood].freeze

  attr_reader :key_source

  def self.for(user, **options)
    organization_key = OrganizationSetting.for(user)&.gistda_api_key
    return new(api_key: organization_key, key_source: "organization", **options) if organization_key.present?

    new(api_key: SystemSetting.current.gistda_api_key, key_source: "system", **options)
  end

  def initialize(api_key:, key_source: "system", base_url: ENV["WEATHER_API_URL"].presence || WeatherFeedClient::DEFAULT_URL,
                 admin_key: ENV["WEATHER_ADMIN_API_KEY"], http: nil)
    @api_key = api_key.to_s.strip.presence
    @key_source = @api_key ? key_source : nil
    @base = URI(base_url)
    @admin_key = admin_key.presence
    @http = http
  end

  def configured? = @api_key.present?

  # FeatureCollection hash (string keys) for `dataset` ("flood" | "hotspots") over the last `period` days,
  # clipped by the weather service to `boundary_wkt` when given.
  def features(dataset, period:, bbox:, boundary_wkt: nil)
    response = request(Net::HTTP::Post, "/api/v1/gistda/features",
                       body: { dataset:, period_days: period, bbox:, boundary_wkt: }.compact, timeout: 90)
    JSON.parse(response.body)
  rescue JSON::ParserError
    raise Error, "weather service returned invalid JSON"
  end

  # [png_bytes, content_type] or nil when GISTDA has no tile there.
  def tile(layer, z:, x:, y:, period: 7)
    response = request(Net::HTTP::Get, "/api/v1/gistda/tiles/#{layer}/#{z.to_i}/#{x.to_i}/#{y.to_i}", params: { period_days: period }, timeout: 30)
    return nil if response.code == "204"

    [response.body, response["Content-Type"].presence || "image/png"]
  end

  private

  def request(klass, path, params: {}, body: nil, timeout: 30)
    raise Error, "WEATHER_ADMIN_API_KEY is not configured" unless @admin_key

    uri = @base.dup
    uri.path = path
    uri.query = URI.encode_www_form(params) if params.present?
    req = klass.new(uri)
    req["Accept"] = "application/json, image/png"
    req["X-API-Key"] = @admin_key
    req["X-Gistda-Api-Key"] = @api_key if @api_key
    if body
      req["Content-Type"] = "application/json"
      req.body = body.to_json
    end
    response = (@http || Net::HTTP).start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: 3, read_timeout: timeout) { |http| http.request(req) }
    return response if response.is_a?(Net::HTTPSuccess)

    code = (JSON.parse(response.body).dig("detail", "code") rescue nil)
    raise MissingKey, "ยังไม่ได้ตั้งค่า GISTDA API key" if code == "gistda_key_missing"
    raise Error, code == "gistda_key_rejected" ? "GISTDA ปฏิเสธ API key (คีย์ไม่ถูกต้องหรือหมดอายุ)" : "บริการข้อมูล GISTDA ไม่พร้อมใช้งาน (HTTP #{response.code})"
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "ติดต่อบริการข้อมูลสภาพอากาศ/GISTDA ไม่ได้ (#{e.class.name.demodulize})"
  end
end

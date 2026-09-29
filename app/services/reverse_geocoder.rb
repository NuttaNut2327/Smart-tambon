require "net/http"

class ReverseGeocoder
  class Error < StandardError; end
  class ConfigurationError < Error; end

  def self.call(latitude:, longitude:)
    api_key = ENV["LONGDO_MAP_KEY"]
    raise ConfigurationError, "ยังไม่ได้กำหนด LONGDO_MAP_KEY" if api_key.blank?

    uri = URI("https://api.longdo.com/map/services/address")
    uri.query = URI.encode_www_form(lat: latitude, lon: longitude, key: api_key, locale: "th", noelevation: 1)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) { |http| http.get(uri.request_uri) }
    raise Error, "ไม่สามารถค้นหาที่อยู่ได้" unless response.is_a?(Net::HTTPSuccess)

    normalize(JSON.parse(response.body)).merge(latitude: latitude, longitude: longitude)
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
    raise Error, "ไม่สามารถเชื่อมต่อบริการค้นหาที่อยู่ได้"
  end

  def self.normalize(payload)
    road = payload["road"].presence || payload["road_name"].presence
    subdistrict = clean_prefix(payload["subdistrict"], %w[ต. แขวง])
    district = clean_prefix(payload["district"], %w[อ. เขต])
    province = clean_prefix(payload["province"], %w[จ. จังหวัด])
    postcode = payload["postcode"].to_s.presence
    parts = [payload["address"].presence, road, subdistrict && "ต.#{subdistrict}", district && "อ.#{district}", province && "จ.#{province}", postcode].compact.uniq
    { address: parts.join(" "), road: road, subdistrict: subdistrict, district: district, province: province, postcode: postcode }
  end
  private_class_method :normalize

  def self.clean_prefix(value, prefixes)
    text = value.to_s.strip
    prefixes.each { |prefix| text = text.delete_prefix(prefix).strip }
    text.presence
  end
  private_class_method :clean_prefix
end

require "net/http"

module Api
  class ReverseGeocodesController < ApplicationController
    def show
      latitude = Float(params[:lat], exception: false)
      longitude = Float(params[:lon], exception: false)
      return render json: { error: "พิกัดไม่ถูกต้อง" }, status: :unprocessable_entity unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)
      return render json: { error: "ยังไม่ได้กำหนด LONGDO_MAP_KEY" }, status: :service_unavailable if api_key.blank?

      payload = fetch_address(latitude, longitude)
      return render json: { error: "ไม่สามารถค้นหาที่อยู่ได้" }, status: :bad_gateway unless payload

      render json: normalize_address(payload).merge(latitude: latitude, longitude: longitude)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      render json: { error: "ไม่สามารถเชื่อมต่อบริการค้นหาที่อยู่ได้" }, status: :bad_gateway
    end

    private

    def api_key
      ENV["LONGDO_MAP_KEY"]
    end

    def fetch_address(latitude, longitude)
      uri = URI("https://api.longdo.com/map/services/address")
      uri.query = URI.encode_www_form(lat: latitude, lon: longitude, key: api_key, locale: "th", noelevation: 1)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) { |http| http.get(uri.request_uri) }
      response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
    end

    def normalize_address(payload)
      road = payload["road"].presence || payload["road_name"].presence
      subdistrict = clean_prefix(payload["subdistrict"], %w[ต. แขวง])
      district = clean_prefix(payload["district"], %w[อ. เขต])
      province = clean_prefix(payload["province"], %w[จ. จังหวัด])
      postcode = payload["postcode"].to_s.presence
      parts = [payload["address"].presence, road, subdistrict && "ต.#{subdistrict}", district && "อ.#{district}", province && "จ.#{province}", postcode].compact.uniq
      { address: parts.join(" "), road: road, subdistrict: subdistrict, district: district, province: province, postcode: postcode }
    end

    def clean_prefix(value, prefixes)
      text = value.to_s.strip
      prefixes.each { |prefix| text = text.delete_prefix(prefix).strip }
      text.presence
    end
  end
end

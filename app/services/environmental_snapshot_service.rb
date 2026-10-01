require "net/http"

class EnvironmentalSnapshotService
  CACHE_TTL = 15.minutes
  GISTDA_URL = "https://pm25.gistda.or.th/rest/getPm25byTambon".freeze
  THAIWATER_URL = "https://api-v3.thaiwater.net/api/v1/thaiwater30/public/thaiwater/weather".freeze
  THAIWATER_TEMPERATURE_URL = "https://api-v3.thaiwater.net/api/v1/thaiwater30/public/thaiwater/temperature".freeze
  WEATHER_URL = "https://api.open-meteo.com/v1/forecast".freeze

  class << self
    def for(subdistricts)
      areas = Array(subdistricts).compact.uniq(&:code)
      return [] if areas.empty?

      cached = EnvironmentalSnapshot.in(subdistrict_code: areas.map { |area| area.code.to_s }).index_by(&:subdistrict_code)
      cached.values.sort_by { |snapshot| snapshot.subdistrict_name.to_s }
    rescue StandardError => error
      Rails.logger.warn("Environmental snapshot read failed: #{error.class}: #{error.message}")
      cached&.values || []
    end

    def sync(subdistricts)
      areas = Array(subdistricts).compact.uniq(&:code)
      return [] if areas.empty?

      pm25_by_code = fetch_pm25(areas)
      thaiwater_by_code = fetch_thaiwater_pm25(areas)
      thaiwater_temperature_by_code = fetch_thaiwater_temperature(areas)
      weather_by_code = fetch_weather(areas)
      areas.map do |area|
        snapshot = EnvironmentalSnapshot.find_or_initialize_by(subdistrict_code: area.code.to_s)
        snapshot.subdistrict_name = area.name_th
        apply_pm25(snapshot, pm25_by_code[area.code.to_s])
        apply_thaiwater_pm25(snapshot, thaiwater_by_code[area.code.to_s])
        apply_weather(snapshot, weather_by_code[area.code.to_s])
        apply_thaiwater_temperature(snapshot, thaiwater_temperature_by_code[area.code.to_s])
        snapshot.expires_at = CACHE_TTL.from_now
        snapshot.save!
        snapshot
      rescue StandardError => error
        Rails.logger.warn("Environmental snapshot sync failed for #{area.code}: #{error.class}: #{error.message}")
        snapshot
      end
    end

    private

    def fetch_pm25(areas)
      areas.group_by { |area| area.district_code.to_s.presence || area.code.to_s.first(4) }.each_with_object({}) do |(district_code, district_areas), result|
        payload = get_json(GISTDA_URL, ap_idn: district_code)
        wanted_codes = district_areas.map { |area| area.code.to_s }
        Array(payload["data"]).each do |row|
          code = row["tb_idn"].to_s
          result[code] = row if wanted_codes.include?(code)
        end
      rescue StandardError => error
        Rails.logger.warn("GISTDA PM2.5 request failed for district #{district_code}: #{error.class}: #{error.message}")
      end
    end

    def fetch_weather(areas)
      areas.each_slice(50).each_with_object({}) do |area_group, result|
        located_areas = area_group.filter_map do |area|
          longitude, latitude = coordinates_for(area)
          [area, longitude, latitude] if longitude && latitude
        end
        next if located_areas.empty?

        payload = get_json(
          WEATHER_URL,
          latitude: located_areas.map { |(_, _, latitude)| latitude }.join(","),
          longitude: located_areas.map { |(_, longitude, _)| longitude }.join(","),
          current: "temperature_2m",
          hourly: "precipitation",
          past_hours: 24,
          forecast_hours: 1,
          timezone: "Asia/Bangkok"
        )
        responses = located_areas.one? ? [payload] : Array(payload)
        located_areas.each_with_index { |(area, _, _), index| result[area.code.to_s] = responses[index] }
      rescue StandardError => error
        Rails.logger.warn("Open-Meteo request failed: #{error.class}: #{error.message}")
      end
    end

    def fetch_thaiwater_pm25(areas)
      wanted_codes = areas.map { |area| area.code.to_s }.to_set
      payload = get_json(THAIWATER_URL, {})
      rows = Array(payload.dig("pm25", "data")).select do |row|
        wanted_codes.include?(thaiwater_subdistrict_code(row)) && row["pm25_value"].present?
      end
      rows.group_by { |row| thaiwater_subdistrict_code(row) }.transform_values do |area_rows|
        newest_time = area_rows.filter_map { |row| parse_thaiwater_time(row["pm25_datetime"]) }.max
        current_rows = newest_time ? area_rows.select { |row| parse_thaiwater_time(row["pm25_datetime"]) == newest_time } : area_rows
        current_rows.max_by { |row| row["pm25_value"].to_f }
      end
    rescue StandardError => error
      Rails.logger.warn("ThaiWater PM2.5 request failed: #{error.class}: #{error.message}")
      {}
    end

    def fetch_thaiwater_temperature(areas)
      wanted_codes = areas.map { |area| area.code.to_s }.to_set
      payload = get_json(THAIWATER_TEMPERATURE_URL, {})
      rows = Array(payload.dig("data", "data")).select do |row|
        observed_at = parse_thaiwater_time(row["temperature_datetime"])
        wanted_codes.include?(thaiwater_subdistrict_code(row)) && row["temperature"].present? &&
          observed_at&.between?(2.hours.ago, Time.current + 5.minutes)
      end
      rows.group_by { |row| thaiwater_subdistrict_code(row) }.transform_values do |area_rows|
        newest_time = area_rows.filter_map { |row| parse_thaiwater_time(row["temperature_datetime"]) }.max
        newest_rows = area_rows.select { |row| parse_thaiwater_time(row["temperature_datetime"]) == newest_time }
        newest_rows.max_by { |row| row["temperature"].to_f }
      end
    rescue StandardError => error
      Rails.logger.warn("ThaiWater temperature request failed: #{error.class}: #{error.message}")
      {}
    end

    def thaiwater_subdistrict_code(row)
      geocode = row["geocode"] || {}
      [geocode["province_code"], geocode["amphoe_code"], geocode["tumbon_code"]].map(&:to_s).join
    end

    def coordinates_for(area)
      return [area.center.x, area.center.y] if area.center

      sql = Subdistrict.sanitize_sql_array([
        "SELECT ST_X(ST_PointOnSurface(boundary::geometry)), ST_Y(ST_PointOnSurface(boundary::geometry)) FROM subdistricts WHERE id = ?",
        area.id
      ])
      Subdistrict.connection.select_rows(sql).first&.map(&:to_f)
    end

    def apply_pm25(snapshot, row)
      return unless row

      snapshot.pm25 = row["pm25"]
      snapshot.pm25_avg_24h = row["pm25Avg24hr"]
      snapshot.pm25_observed_at = parse_gistda_time(row["dt"]) if row["dt"].present?
    rescue ArgumentError
      snapshot.pm25_observed_at = nil
    end

    def parse_gistda_time(value)
      raw = value.to_s
      parsed = Time.zone.parse(raw)
      return parsed unless parsed > 30.minutes.from_now && raw.end_with?("Z")

      # The GISTDA tambon endpoint occasionally labels a Thailand local clock
      # value with Z. Treat it as local time only when normal UTC parsing would
      # produce an impossible future observation.
      Time.zone.parse(raw.delete_suffix("Z"))
    end

    def apply_weather(snapshot, payload)
      return unless payload

      snapshot.temperature_c = payload.dig("current", "temperature_2m")
      snapshot.temperature_source = "open_meteo"
      snapshot.temperature_source_label = "ข้อมูลประมาณการจากแบบจำลอง Open-Meteo"
      snapshot.temperature_station_id = nil
      snapshot.temperature_station_name = nil
      snapshot.temperature_station_agency = nil
      precipitation = Array(payload.dig("hourly", "precipitation")).compact.map(&:to_f)
      snapshot.rain_24h_mm = precipitation.first(24).sum.round(1)
      snapshot.weather_observed_at = Time.zone.parse(payload.dig("current", "time").to_s)
      snapshot.temperature_observed_at = snapshot.weather_observed_at
    rescue ArgumentError
      snapshot.weather_observed_at = Time.current
    end

    def apply_thaiwater_temperature(snapshot, row)
      return unless row

      station = row["station"] || {}
      snapshot.temperature_c = row["temperature"]
      snapshot.temperature_source = "thaiwater"
      snapshot.temperature_source_label = "ข้อมูลตรวจวัดจากสถานี ThaiWater"
      snapshot.temperature_observed_at = parse_thaiwater_time(row["temperature_datetime"])
      snapshot.temperature_station_id = station["id"].to_s
      snapshot.temperature_station_name = station.dig("tele_station_name", "th").presence || station["tele_station_oldcode"]
      snapshot.temperature_station_agency = row.dig("agency", "agency_name", "th")
    end

    def apply_thaiwater_pm25(snapshot, row)
      return unless row

      station = row["station"] || {}
      snapshot.thaiwater_pm25 = row["pm25_value"]
      snapshot.thaiwater_pm25_avg_24h = row["pm25_avg_24h"]
      snapshot.thaiwater_pm25_observed_at = parse_thaiwater_time(row["pm25_datetime"])
      snapshot.thaiwater_station_id = station["id"].to_s
      snapshot.thaiwater_station_name = station.dig("tele_station_name", "th").presence || station["tele_station_oldcode"]
      snapshot.thaiwater_station_agency = row.dig("agency", "agency_name", "th")
    end

    def parse_thaiwater_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def get_json(url, parameters)
      uri = URI(url)
      uri.query = URI.encode_www_form(parameters)
      request = Net::HTTP::Get.new(uri, "Accept" => "application/json", "User-Agent" => "SmartTambon/1.0")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end

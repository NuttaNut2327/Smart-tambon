require "json"
require "net/http"

class ThaiwaterStationSync
  WATER_LEVEL_URL = URI("https://api-v3.thaiwater.net/api/v1/thaiwater30/public/waterlevel_load")
  RAINFALL_URL = URI("https://api-v3.thaiwater.net/api/v1/thaiwater30/public/rain_24h")
  FUTURE_TOLERANCE = 5.minutes

  def call
    seen_source_ids = []
    import_water_levels(fetch_json(WATER_LEVEL_URL).dig("waterlevel_data", "data"), seen_source_ids)
    import_rainfall(fetch_json(RAINFALL_URL)["data"], seen_source_ids)
    seen_source_ids.uniq!
    mark_missing(seen_source_ids)
    seen_source_ids.size
  end

  private

  def import_water_levels(rows, seen_source_ids)
    Array(rows).each do |row|
      station_data = row["station"] || {}
      observed_at = valid_timestamp(row["waterlevel_datetime"])
      station = station_for(row, station_data)
      WaterStationMetadataUpdater.call(station,
        common_attributes(row, station_data).merge(source_payload: { "water_level" => row }))
      WaterStationReadingUpdater.call(station:, payload: row, attributes: {
        water_level_m_msl: number(row["waterlevel_msl"]), water_level_observed_at: observed_at,
        water_level_source: "thaiwater", river_capacity_percent: number(row["storage_percent"]),
        source_observed_at: observed_at
      })
      seen_source_ids << station.source_station_id
    rescue ActiveRecord::RecordInvalid, ArgumentError, TypeError
      next
    end
  end

  def import_rainfall(rows, seen_source_ids)
    Array(rows).each do |row|
      station_data = row["station"] || {}
      observed_at = valid_timestamp(row["rainfall_datetime"])
      station = station_for(row, station_data)
      unless station.persisted? && station.latest_reading&.water_level_observed_at.present?
        WaterStationMetadataUpdater.call(station,
          common_attributes(row, station_data).merge(source_payload: { "rainfall" => row }))
      end
      WaterStationReadingUpdater.call(station:, payload: row, attributes: {
        rainfall_value: number(row["rain_24h"]), rainfall_observed_at: observed_at,
        rainfall_source: "thaiwater", source_observed_at: observed_at
      })
      seen_source_ids << station.source_station_id
    rescue ActiveRecord::RecordInvalid, ArgumentError, TypeError
      next
    end
  end

  def station_for(row, station_data)
    source_id = station_data["id"].to_s
    WaterStation.find_or_initialize_by(source: "thaiwater", source_station_id: source_id).tap do |station|
      station.station_id ||= "thaiwater:#{source_id}"
    end
  end

  def common_attributes(row, station_data)
    agency = row["agency"] || {}
    geocode = row["geocode"] || {}
    basin = row["basin"] || {}
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    longitude = Float(station_data["tele_station_long"])
    latitude = Float(station_data["tele_station_lat"])
    {
      station_code: station_data["tele_station_oldcode"],
      station_name_th: station_data.dig("tele_station_name", "th"),
      station_name_en: station_data.dig("tele_station_name", "en"),
      agency: agency.dig("agency_shortname", "en"),
      agency_name: agency.dig("agency_name", "th"),
      province_code: geocode["province_code"], province_name_th: geocode.dig("province_name", "th"),
      district_name_th: geocode.dig("amphoe_name", "th"), subdistrict_name_th: geocode.dig("tumbon_name", "th"),
      main_basin_code: basin["basin_code"], main_basin_name_th: basin.dig("basin_name", "th"),
      location: factory.point(longitude, latitude),
      source_metadata: { provider: "ThaiWater", owner: agency.dig("agency_name", "th") },
      canonical_station_key: WaterStationCanonicalizer.key(agency: agency.dig("agency_shortname", "en"),
        code: station_data["tele_station_oldcode"], name: station_data.dig("tele_station_name", "th"), longitude:, latitude:),
      sync_status: "online", missing_sync_count: 0
    }
  end

  def fetch_json(uri)
    request = Net::HTTP::Get.new(uri, "Accept" => "application/json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
    raise "ThaiWater API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def valid_timestamp(value)
    timestamp = Time.zone.parse(value.to_s)
    timestamp if timestamp <= Time.current + FUTURE_TOLERANCE
  rescue ArgumentError
    nil
  end

  def number(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def mark_missing(seen_source_ids)
    WaterStation.where(source: "thaiwater").where.not(source_station_id: seen_source_ids)
      .update_all("missing_sync_count = missing_sync_count + 1, sync_status = CASE WHEN missing_sync_count + 1 >= 3 THEN 'disconnected' ELSE sync_status END")
  end
end

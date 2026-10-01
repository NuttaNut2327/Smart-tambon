require "json"
require "net/http"

class DwrStationSync
  API_URL = URI("https://telemetry.dwr.go.th/api/public/teleMap/stnSearch")
  FILTER = {
    waterStatusMode: "RiverBasinCapStatus", mode: "ANY", onlyCCTV: false,
    eqWl: true, eqRf: true, eqCctv: true, agencyDwr: true, agencyRid: false,
    agencyHii: false, agencyEws: false, agencyEgat: false, rfLvNone: true,
    rfLvLight: true, rfLvModerate: true, rfLvHeavy: true, rfLvVeryHeavy: true,
    rbCapCritLow: true, rbCapLow: true, rbCapNormal: true, rbCapHigh: true, rbCapOverCap: true
  }.freeze

  def call
    markers = fetch_markers
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    seen_source_ids = []

    WaterStation.transaction do
      markers.each do |marker|
        point = marker["point"] || {}
        latitude = Float(point["lat"])
        longitude = Float(point["lon"])
        station_id = marker["id"].to_s
        next if station_id.blank?

        address = marker["addressInfo"] || {}
        province = marker["provinceInfo"] || address["provinceInfo"] || {}
        district = address["districtInfo"] || {}
        subdistrict = address["subDistrictInfo"] || {}
        station = WaterStation.find_by(source: "dwr", source_station_id: station_id) ||
          WaterStation.find_or_initialize_by(station_id: station_id)
        station.station_id ||= station_id
        water_level_at = timestamp(marker["currWlTimestamp"])
        rainfall_at = timestamp(marker["currRfTimestamp"])
        WaterStationMetadataUpdater.call(station, {
          station_code: marker["code"], station_name_th: marker["nameTh"], station_name_en: marker["nameEn"],
          agency: marker["agency"], province_code: province["code"], province_name_th: province["nameTh"],
          district_name_th: district["nameTh"], subdistrict_name_th: subdistrict["nameTh"],
          main_basin_code: marker.dig("mainBasinInfo", "code"), main_basin_name_th: marker.dig("mainBasinInfo", "nameTh"),
          sub_basin_code: marker.dig("subBasinInfo", "code"), sub_basin_name_th: marker.dig("subBasinInfo", "nameTh"),
          equipment: Array(marker["stnEquipments"]), location: factory.point(longitude, latitude), source_payload: marker,
          source: "dwr", source_station_id: station_id, agency_name: "กรมทรัพยากรน้ำ",
          source_metadata: { provider: "DWR", owner: "กรมทรัพยากรน้ำ" },
          canonical_station_key: WaterStationCanonicalizer.key(agency: marker["agency"], code: marker["code"],
            name: marker["nameTh"], longitude:, latitude:),
          sync_status: "online", missing_sync_count: 0
        })
        WaterStationReadingUpdater.call(station:, payload: marker, attributes: {
          water_level_m_msl: number(marker["currWaterLevelValue"]), water_level_observed_at: water_level_at,
          water_level_source: "dwr", rainfall_value: number(marker["currRainfallValue"]),
          rainfall_observed_at: rainfall_at, rainfall_source: "dwr",
          flow_rate_m3_s: number(marker["currFlowRateValue"]), river_capacity_percent: number(marker["currRiverBasinCapValue"]),
          source_observed_at: timestamp(marker["currDataTimestamp"])
        })
        seen_source_ids << station_id
      rescue ArgumentError, TypeError
        next
      end
    end

    mark_missing("dwr", seen_source_ids)
    seen_source_ids.size
  end

  private

  def fetch_markers
    request = Net::HTTP::Post.new(API_URL, "Accept" => "application/json", "Content-Type" => "application/json")
    request.body = { filter: FILTER }.to_json
    response = Net::HTTP.start(API_URL.host, API_URL.port, use_ssl: true, read_timeout: 60) { |http| http.request(request) }
    raise "DWR API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("value")
  end

  def number(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def timestamp(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def mark_missing(source, seen_source_ids)
    scope = WaterStation.where(source:).where.not(source_station_id: seen_source_ids)
    scope.update_all("missing_sync_count = missing_sync_count + 1, sync_status = CASE WHEN missing_sync_count + 1 >= 3 THEN 'disconnected' ELSE sync_status END")
  end
end

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
    imported = 0

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
        station = WaterStation.find_or_initialize_by(station_id: station_id)
        station.assign_attributes(
          station_code: marker["code"], station_name_th: marker["nameTh"], station_name_en: marker["nameEn"],
          agency: marker["agency"], province_code: province["code"], province_name_th: province["nameTh"],
          district_name_th: district["nameTh"], subdistrict_name_th: subdistrict["nameTh"],
          main_basin_code: marker.dig("mainBasinInfo", "code"), main_basin_name_th: marker.dig("mainBasinInfo", "nameTh"),
          sub_basin_code: marker.dig("subBasinInfo", "code"), sub_basin_name_th: marker.dig("subBasinInfo", "nameTh"),
          equipment: Array(marker["stnEquipments"]), water_level_m_msl: number(marker["currWaterLevelValue"]),
          water_level_observed_at: timestamp(marker["currWlTimestamp"]), rainfall_value: number(marker["currRainfallValue"]),
          rainfall_observed_at: timestamp(marker["currRfTimestamp"]), flow_rate_m3_s: number(marker["currFlowRateValue"]),
          river_capacity_percent: number(marker["currRiverBasinCapValue"]), source_observed_at: timestamp(marker["currDataTimestamp"]),
          location: factory.point(longitude, latitude), source_payload: marker
        )
        station.save!
        imported += 1
      rescue ArgumentError, TypeError
        next
      end
    end

    imported
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
end

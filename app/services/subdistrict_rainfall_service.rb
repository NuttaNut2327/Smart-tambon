class SubdistrictRainfallService
  class << self
    def resolve(subdistricts, snapshots)
      snapshots_by_code = Array(snapshots).index_by { |snapshot| snapshot.subdistrict_code.to_s }

      Array(subdistricts).each_with_object({}) do |subdistrict, result|
        code = subdistrict.code.to_s
        station = latest_rainfall_station(subdistrict)
        result[code] = station ? station_result(station) : model_result(snapshots_by_code[code])
      end
    end

    private

    def latest_rainfall_station(subdistrict)
      return unless subdistrict.boundary

      stations = WaterStation.inside(subdistrict.boundary).joins(:latest_reading)
        .where.not(water_station_latest_readings: { rainfall_value: nil })
        .where(water_station_latest_readings: { rainfall_observed_at: (1.hour.ago - 5.minutes)..(Time.current + 5.minutes) })
        .includes(:latest_reading).to_a
      stations.min_by do |station|
        [{ "own" => 0, "dwr" => 1, "thaiwater" => 2 }.fetch(station.rainfall_source.presence || station.source, 9),
          -(station.rainfall_observed_at&.to_i || 0)]
      end
    end

    def station_result(station)
      {
        value: station.rainfall_value&.round(1),
        observed_at: station.rainfall_observed_at || station.source_observed_at || station.updated_at,
        source: station.rainfall_source.presence || station.source,
        source_label: station.source == "dwr" ? "ข้อมูลตรวจวัดจากสถานี DWR" : "ข้อมูลตรวจวัดจาก #{station.source_label}",
        station_name: station.station_name_th.presence || station.station_name_en.presence || station.station_code,
        station_code: station.station_code
      }
    end

    def model_result(snapshot)
      {
        value: snapshot&.rain_24h_mm&.round(1),
        observed_at: snapshot&.weather_observed_at,
        source: "open_meteo",
        source_label: "ข้อมูลประมาณการจากแบบจำลอง Open-Meteo",
        station_name: nil,
        station_code: nil
      }
    end
  end
end

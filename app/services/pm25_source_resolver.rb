class Pm25SourceResolver
  class << self
    def resolve(user:, subdistricts:, snapshots:)
      snapshots_by_code = Array(snapshots).index_by { |snapshot| snapshot.subdistrict_code.to_s }
      own_by_code = own_sensor_readings(user, subdistricts)

      Array(subdistricts).each_with_object({}) do |subdistrict, result|
        code = subdistrict.code.to_s
        result[code] = own_by_code[code] || thaiwater_result(snapshots_by_code[code]) || gistda_result(snapshots_by_code[code])
      end
    end

    private

    def own_sensor_readings(user, subdistricts)
      datasets = ImportedDataset.visible_to(user).where(data_type: "pm25_sensors").to_a
      dataset_by_id = datasets.index_by(&:id)
      readings = Pm25SensorReading.where(:imported_dataset_id.in => dataset_by_id.keys).desc(:observed_at).to_a
      subdistrict_by_id = subdistricts.index_by(&:id)

      readings.each_with_object({}) do |reading, result|
        dataset = dataset_by_id[reading.imported_dataset_id]
        subdistrict = subdistrict_by_id[dataset&.subdistrict_id] || locate_subdistrict(subdistricts, reading)
        next unless subdistrict

        code = subdistrict.code.to_s
        candidate = sensor_result(reading)
        result[code] = candidate if result[code].nil? || candidate[:observed_at] > result[code][:observed_at]
      end
    end

    def locate_subdistrict(subdistricts, reading)
      return if reading.latitude.blank? || reading.longitude.blank?

      subdistricts.find do |subdistrict|
        Subdistrict.where(id: subdistrict.id)
          .where("ST_Covers(boundary, ST_SetSRID(ST_Point(?, ?), 4326))", reading.longitude, reading.latitude).exists?
      end
    end

    def sensor_result(reading)
      { value: reading.pm25&.round(1), avg_24h: reading.pm25_avg_24h&.round(1), observed_at: reading.observed_at,
        source: "own_sensor", source_label: "ข้อมูลตรวจวัดจากเซนเซอร์ในพื้นที่", station_name: reading.sensor_id }
    end

    def thaiwater_result(snapshot)
      return unless snapshot&.thaiwater_pm25.present?

      { value: snapshot.thaiwater_pm25&.round(1), avg_24h: snapshot.thaiwater_pm25_avg_24h&.round(1),
        observed_at: snapshot.thaiwater_pm25_observed_at, source: "thaiwater",
        source_label: "ข้อมูลตรวจวัดจากสถานี ThaiWater", station_name: snapshot.thaiwater_station_name,
        station_id: snapshot.thaiwater_station_id, agency: snapshot.thaiwater_station_agency }
    end

    def gistda_result(snapshot)
      { value: snapshot&.pm25&.round(1), avg_24h: snapshot&.pm25_avg_24h&.round(1), observed_at: snapshot&.pm25_observed_at,
        source: "gistda", source_label: "ข้อมูลวิเคราะห์เชิงพื้นที่จาก GISTDA", station_name: nil }
    end
  end
end

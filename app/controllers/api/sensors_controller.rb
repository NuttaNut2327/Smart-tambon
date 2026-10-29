module Api
  # Read side for signed-in users: registered sensors with their latest value, and per-sensor history.
  class SensorsController < ApplicationController
    MAX_READINGS = 1000

    def index
      types = params[:type].present? ? [params[:type].to_s] : SensorIngestion::TYPES.keys
      return render json: { error: "ไม่รู้จักประเภทเซนเซอร์" }, status: :unprocessable_entity unless (types - SensorIngestion::TYPES.keys).empty?

      sensors = types.flat_map do |type|
        config = SensorIngestion::TYPES.fetch(type)
        ImportedDataset.visible_to(current_user).where(data_type: config[:dataset_type]).flat_map do |dataset|
          Array(dataset.current_version&.records).filter_map do |record|
            next if record["sensor_id"].blank?

            latest = config[:model].where(imported_dataset_id: dataset.id, sensor_id: record["sensor_id"].to_s).desc(:observed_at).first
            position = config[:moving] && latest ? latest : record
            { sensor_type: type, sensor_id: record["sensor_id"].to_s, dataset_id: dataset.id.to_s,
              latitude: position["latitude"], longitude: position["longitude"], latest: latest&.as_reading_json }
          end
        end
      end
      render json: sensors
    end

    def readings
      config = SensorIngestion::TYPES[params[:sensor_type].to_s]
      return render json: { error: "ไม่รู้จักประเภทเซนเซอร์" }, status: :unprocessable_entity unless config

      datasets = ImportedDataset.visible_to(current_user).where(data_type: config[:dataset_type]).only(:_id, :current_version_id).to_a
      registered = ImportedDatasetRecord.where(:imported_dataset_version_id.in => datasets.map(&:current_version_id).compact,
                                               "payload.sensor_id" => params[:sensor_id].to_s).exists?
      return render json: { error: "ไม่พบเซนเซอร์นี้ในพื้นที่ที่คุณเข้าถึงได้" }, status: :not_found unless registered

      scope = config[:model].where(:imported_dataset_id.in => datasets.map(&:id), sensor_id: params[:sensor_id].to_s)

      from = parse_time(params[:from])
      to = parse_time(params[:to])
      scope = scope.where(:observed_at.gte => from) if from
      scope = scope.where(:observed_at.lte => to) if to
      limit = params[:limit].to_i.clamp(1, MAX_READINGS)
      limit = 100 if params[:limit].blank?
      render json: { sensor_type: params[:sensor_type], sensor_id: params[:sensor_id],
                     readings: scope.desc(:observed_at).limit(limit).map(&:as_reading_json) }
    end

    private

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end

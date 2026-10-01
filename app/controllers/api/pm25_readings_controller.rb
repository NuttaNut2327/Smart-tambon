module Api
  class Pm25ReadingsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :require_access_configuration!
    skip_forgery_protection

    def create
      dataset, sensor = find_sensor!
      value = Float(params[:pm25] || params[:value])
      observed_at = Time.zone.parse(params[:observed_at].presence || Time.current.iso8601)
      reading = Pm25SensorReading.create!(
        imported_dataset_id: dataset.id,
        sensor_id: sensor.fetch("sensor_id"),
        pm25: value,
        pm25_avg_24h: Float(params[:pm25_avg_24h], exception: false),
        observed_at:,
        latitude: sensor["latitude"],
        longitude: sensor["longitude"]
      )
      render json: { status: "accepted", sensor_id: reading.sensor_id, observed_at: reading.observed_at.iso8601 }, status: :created
    rescue KeyError, ArgumentError, TypeError
      render json: { error: "ข้อมูล PM2.5 หรือเวลาไม่ถูกต้อง" }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotFound
      render json: { error: "ไม่พบ Sensor Token" }, status: :unauthorized
    end

    private

    def find_sensor!
      token = request.authorization.to_s.delete_prefix("Bearer ").presence || request.headers["X-Sensor-Token"].presence || params[:token].presence
      raise ActiveRecord::RecordNotFound if token.blank?

      ImportedDataset.where(data_type: "pm25_sensors").each do |dataset|
        sensor = Array(dataset.current_version&.records).find { |record| secure_token_match?(record["token"], token) }
        return [dataset, sensor] if sensor
      end
      raise ActiveRecord::RecordNotFound
    end

    def secure_token_match?(stored, supplied)
      return false if stored.blank?

      ActiveSupport::SecurityUtils.secure_compare(
        OpenSSL::Digest::SHA256.hexdigest(stored.to_s),
        OpenSSL::Digest::SHA256.hexdigest(supplied.to_s)
      )
    end
  end
end

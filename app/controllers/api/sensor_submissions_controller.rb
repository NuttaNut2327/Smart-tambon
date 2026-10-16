module Api
  # Device-facing endpoint: sensors authenticate with their own token, not a user session.
  class SensorSubmissionsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :require_access_configuration!
    skip_forgery_protection

    def create
      result = SensorIngestion.call(
        sensor_type:, sensor_id: params[:sensor_id], token: sensor_token,
        payload: request.request_parameters.presence || params.to_unsafe_h.except(:controller, :action, :format), source: "http"
      )
      render json: { status: result.duplicate ? "duplicate" : "accepted", sensor_id: result.reading.sensor_id,
                     observed_at: result.reading.observed_at.iso8601 }, status: result.duplicate ? :ok : :created
    rescue SensorIngestion::Unauthorized => error
      render json: { error: error.message }, status: :unauthorized
    rescue SensorIngestion::Invalid => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def sensor_type = raise(NotImplementedError)

    def sensor_token
      request.authorization.to_s.delete_prefix("Bearer ").presence || request.headers["X-Sensor-Token"].presence || params[:token].presence
    end
  end
end

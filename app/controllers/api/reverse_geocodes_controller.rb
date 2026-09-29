module Api
  class ReverseGeocodesController < ApplicationController
    def show
      latitude = Float(params[:lat], exception: false)
      longitude = Float(params[:lon], exception: false)
      return render json: { error: "พิกัดไม่ถูกต้อง" }, status: :unprocessable_entity unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)
      render json: ReverseGeocoder.call(latitude: latitude, longitude: longitude)
    rescue ReverseGeocoder::ConfigurationError => error
      render json: { error: error.message }, status: :service_unavailable
    rescue ReverseGeocoder::Error => error
      render json: { error: error.message }, status: :bad_gateway
    end
  end
end

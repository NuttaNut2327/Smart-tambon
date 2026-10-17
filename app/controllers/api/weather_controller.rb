module Api
  class WeatherController < ApplicationController
    def show
      render json: WeatherPanelService.new(user: current_user, global_viewer: global_viewer?)
                                      .call(location_id: params[:location_id])
    rescue WeatherFeedClient::Error => e
      Rails.logger.warn("[weather] #{e.message}")
      render json: { error: "ยังเชื่อมต่อบริการข้อมูลสภาพอากาศไม่ได้" }, status: :service_unavailable
    end
  end
end

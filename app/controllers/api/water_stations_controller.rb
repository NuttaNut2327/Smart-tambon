module Api
  class WaterStationsController < ApplicationController
    def index
      stations = WaterStation.includes(:latest_reading).order(:station_code)
      unless global_viewer?
        boundary = current_user.access_boundary
        stations = boundary ? stations.inside(boundary) : stations.none
      end

      payload = if global_viewer?
        cache_key = [
          "water-stations/map/v2",
          WaterStation.maximum(:updated_at)&.to_i,
          WaterStationLatestReading.maximum(:updated_at)&.to_i
        ].join(":")
        Rails.cache.fetch(cache_key, expires_in: 15.minutes) { WaterStationMapService.call(stations) }
      else
        WaterStationMapService.call(stations)
      end

      render json: payload
    end
  end
end

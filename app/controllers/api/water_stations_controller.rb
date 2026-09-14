module Api
  class WaterStationsController < ApplicationController
    def index
      stations = WaterStation.order(:station_code)
      unless global_viewer?
        boundary = current_user.access_boundary
        stations = boundary ? stations.inside(boundary) : stations.none
      end
      render json: stations.map(&:as_map_json)
    end
  end
end

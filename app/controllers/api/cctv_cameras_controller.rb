module Api
  class CctvCamerasController < ApplicationController
    def index
      cameras = CctvCamera.visible_to(current_user).order_by(name: :asc).to_a
      render json: cameras.map(&:as_map_json)
    end
  end
end

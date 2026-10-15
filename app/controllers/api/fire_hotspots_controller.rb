module Api
  class FireHotspotsController < ApplicationController
    def index
      hours = params.fetch(:hours, 24).to_f.clamp(1, 24 * 7)
      hotspots = FireHotspot.recent(hours).order(acquired_at: :desc)
      unless global_viewer?
        boundary = current_user.access_boundary
        hotspots = boundary ? hotspots.inside(boundary) : hotspots.none
      end

      render json: {
        hours:,
        synced_at: FireHotspot.maximum(:updated_at)&.iso8601,
        count: hotspots.size,
        hotspots: hotspots.limit(5000).map(&:as_map_json)
      }
    end
  end
end

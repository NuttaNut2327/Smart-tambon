module Api
  class DynamicLayersController < ApplicationController
    def index
      items = DynamicLayer.where(active: true)
      unless global_viewer?
        items = items.any_of({ owner_user_id: current_user.id }, { shared_with_all: true })
        items = filter_to_access_boundary(items, current_user.access_boundary) if current_user.access_area&.boundary
      end
      items = items.where(layer_key: params[:layer_key]) if params[:layer_key].present?
      render json: items.limit(1_000).map { |x| x.attributes.except("_id") }
    end

    private

    def filter_to_access_boundary(items, boundary)
      factory = RGeo::Geographic.spherical_factory(srid: 4326)
      items.to_a.select do |item|
        coordinates = item.location
        coordinates.is_a?(Array) && coordinates.length >= 2 && boundary.covers?(factory.point(coordinates[0], coordinates[1]))
      rescue StandardError
        false
      end
    end
  end
end

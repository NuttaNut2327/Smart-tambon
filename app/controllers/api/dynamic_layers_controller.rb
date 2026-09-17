module Api
  class DynamicLayersController < ApplicationController
    def index
      items = DynamicLayer.where(active: true)
      items = items.where(layer_key: params[:layer_key]) if params[:layer_key].present?
      unless global_viewer?
        items = items.any_of({ owner_user_id: current_user.id }, { shared_with_all: true }) unless current_user.subdistrict_admin?
        items = filter_to_access_boundary(items, current_user.access_boundary)
      end
      items = items.limit(1_000) if items.respond_to?(:limit)
      render json: items.first(1_000).map { |x| x.attributes.except("_id") }
    end

    private

    def filter_to_access_boundary(items, boundary)
      return [] unless boundary

      AccessBoundaryPointFilter.new(boundary).filter(items.to_a) { |item| Array(item.location).first(2) }
    end
  end
end

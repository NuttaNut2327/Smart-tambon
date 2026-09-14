module Api
  class ProvincesController < ApplicationController
    def index
      provinces = global_viewer? ? Province.alphabetical : Province.where(id: current_user.subdistrict.province_id)
      if params[:geometry] == "1"
        simplified = params[:simplified] == "3d"
        features = if simplified
          boundary_cache("provinces:#{global_viewer? ? 'all' : current_user.subdistrict.province_id}:3d", provinces.maximum(:updated_at)) do
            provinces.filter_map { |province| province.as_geojson(simplified: true) if province.boundary.present? }
          end
        else
          provinces.filter_map { |province| province.as_geojson if province.boundary.present? }
        end
        return render json: {
          type: "FeatureCollection",
          features: features
        }
      end

      render json: provinces.select(:id, :code, :name_th, :name_en)
    end
    def show
      province = Province.find(params[:id])
      return render_forbidden unless global_viewer? || current_user.subdistrict&.province_id == province.id

      if params[:simplified] == "3d"
        return render json: boundary_cache("province:#{province.id}:3d", province.updated_at) { province.as_geojson(simplified: true) }
      end

      render json: province.as_geojson
    end

    private

    def boundary_cache(key, version, &)
      BoundaryGeojsonCacheStore.fetch(key, source_version: version&.utc&.iso8601(6) || "none", &)
    end
  end
end

module Api
  class DistrictsController < ApplicationController
    before_action :load_province

    def index
      districts = cached_districts if params[:simplified] == "3d"
      districts ||= DistrictBoundary.for_province(@province)
      return render json: { type: "FeatureCollection", features: districts } if params[:geometry] == "1"

      render json: districts.map { |district| (district[:properties] || district["properties"]).merge(id: district[:id] || district["id"]) }
    end

    def show
      districts = params[:simplified] == "3d" ? cached_districts : DistrictBoundary.for_province(@province)
      district = districts.find { |feature| (feature[:id] || feature["id"]).to_s == params[:id].to_s }
      return render json: { error: "ไม่พบอำเภอ" }, status: :not_found unless district

      render json: district
    end

    private

    def load_province
      @province = Province.find(params[:province_id])
      return if global_viewer? || current_user.subdistrict&.province_id == @province.id

      render_forbidden
    end

    def cached_districts
      version = @province.subdistricts.maximum(:updated_at)&.utc&.iso8601(6) || "none"
      BoundaryGeojsonCacheStore.fetch("districts:#{@province.id}:3d", source_version: version) do
        DistrictBoundary.for_province(@province, simplified: true)
      end
    end
  end
end

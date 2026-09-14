module Api
  class SubdistrictsController < ApplicationController
    def index
      province = Province.find(params[:province_id])
      return render_forbidden unless global_viewer? || province.id == current_user.subdistrict.province_id

      show_province_boundaries = params[:geometry] == "1" && current_user.subdistrict_admin?
      subdistricts = if global_viewer? || show_province_boundaries
        province.subdistricts.alphabetical
      else
        province.subdistricts.where(id: current_user.subdistrict_id)
      end
      requested_district_code = params[:district_code].to_s.presence
      subdistricts = subdistricts.where(district_code: requested_district_code) if requested_district_code
      if params[:geometry] == "1"
        simplified = params[:simplified] == "3d"
        features = if simplified
          boundary_cache("subdistricts:#{province.id}:#{requested_district_code || 'all'}:3d", subdistricts.maximum(:updated_at)) do
            subdistricts.filter_map { |subdistrict| subdistrict.as_geojson(simplified: true) if subdistrict.boundary.present? }
          end
        else
          subdistricts.filter_map { |subdistrict| subdistrict.as_geojson if subdistrict.boundary.present? }
        end
        restricted_boundaries = show_province_boundaries && !global_viewer?
        render json: {
          type: "FeatureCollection",
          features: features.filter_map do |feature|
            if restricted_boundaries
              { type: "Feature", id: feature[:id] || feature["id"], properties: { restrictedBoundary: true }, geometry: feature[:geometry] || feature["geometry"] }
            else
              feature
            end
          end
        }
      else
        render json: subdistricts.select(:id, :code, :name_th, :name_en, :district_code, :district_name_th)
      end
    end
    def show
      subdistrict = Subdistrict.find(params[:id])
      return render_forbidden unless authorized_for_subdistrict?(subdistrict)

      if params[:simplified] == "3d"
        return render json: boundary_cache("subdistrict:#{subdistrict.id}:3d", subdistrict.updated_at) { subdistrict.as_geojson(simplified: true) }
      end

      render json: subdistrict.as_geojson
    end

    def locate
      lon = Float(params[:lon], exception: false)
      lat = Float(params[:lat], exception: false)
      unless lon && lat && (-180..180).cover?(lon) && (-90..90).cover?(lat)
        return render json: { error: "พิกัดไม่ถูกต้อง" }, status: :unprocessable_entity
      end

      subdistrict = Subdistrict.where(
        "ST_Covers(boundary, ST_SetSRID(ST_Point(?, ?), 4326)::geography)", lon, lat
      ).first
      return render json: { error: "ไม่พบตำบลที่พิกัดนี้" }, status: :not_found unless subdistrict
      return render_forbidden unless authorized_for_subdistrict?(subdistrict)

      render json: {
        id: subdistrict.id,
        name_th: subdistrict.name_th,
        province_id: subdistrict.province_id,
        province_name_th: subdistrict.province.name_th,
        district_code: subdistrict.district_code,
        district_name_th: subdistrict.district_name_th
      }
    end

    def search
      query = params[:query].to_s.strip
      return render json: [] if query.blank?

      normalized_query = query.sub(/\A(?:จังหวัด|ตำบล|แขวง|จ\.|ต\.)\s*/i, "").strip
      return render json: [] if normalized_query.blank?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(normalized_query)}%"
      provinces = Province.where("name_th ILIKE ? OR name_en ILIKE ?", pattern, pattern)
        .alphabetical
        .limit(10)
        .map do |province|
          {
            result_type: "province",
            id: province.id,
            name_th: province.name_th,
            name_en: province.name_en
          }
        end
      subdistricts = Subdistrict.includes(:province)
        .where("subdistricts.name_th ILIKE ? OR subdistricts.name_en ILIKE ? OR subdistricts.code ILIKE ?", pattern, pattern, pattern)
        .order(:name_th)
        .limit(15)
        .map do |subdistrict|
          {
            result_type: "subdistrict",
            id: subdistrict.id,
            code: subdistrict.code,
            name_th: subdistrict.name_th,
            name_en: subdistrict.name_en,
            district_name_th: subdistrict.district_name_th,
            province_id: subdistrict.province_id,
            province_name_th: subdistrict.province.name_th
          }
        end
      unless global_viewer?
        provinces = []
        subdistricts = subdistricts.select { |subdistrict| subdistrict[:id] == current_user.subdistrict_id }
      end
      render json: provinces + subdistricts
    end

    private

    def boundary_cache(key, version, &)
      BoundaryGeojsonCacheStore.fetch(key, source_version: version&.utc&.iso8601(6) || "none", &)
    end
  end
end

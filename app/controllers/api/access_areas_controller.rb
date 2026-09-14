module Api
  class AccessAreasController < ApplicationController
    def show
      return render_forbidden if current_user.system_admin?

      area = current_user.access_area
      return render json: current_user.subdistrict.as_geojson if area.blank?

      render json: area.as_geojson
    end
  end
end

class DataLayersController < ApplicationController
  def show
    @can_upload = current_user.system_admin? || current_user.subdistrict_admin?
    @population_datasets = PopulationDataset.includes(subdistrict: :province).visible_to(current_user).order(created_at: :desc)
    @area_label = if current_user.access_area&.name.present?
                    current_user.access_area.name
                  elsif current_user.subdistrict
                    "#{current_user.subdistrict.name_th}, #{current_user.subdistrict.province.name_th}"
                  else
                    "ทุกพื้นที่"
                  end
  end
end

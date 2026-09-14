class PopulationDataset < ApplicationRecord
  belongs_to :subdistrict
  belongs_to :user

  validates :name, :source_file, presence: true

  scope :visible_to, ->(user) do
    next all if user.system_admin?

    scope = where("population_datasets.user_id = ? OR population_datasets.shared_with_all = ?", user.id, true)
    if user.access_area&.boundary
      scope.joins(:subdistrict).where("ST_Intersects(subdistricts.boundary, ?)", user.access_area.boundary)
    else
      scope.where(subdistrict_id: user.accessible_subdistrict_ids)
    end
  end
end

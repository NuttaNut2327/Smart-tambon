class AnalysisRecord < ApplicationRecord
  belongs_to :user
  belongs_to :subdistrict, optional: true

  validates :name, :selection_type, :geometry, presence: true
end

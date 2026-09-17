class UserAccessArea < ApplicationRecord
  belongs_to :user

  validates :name, :source, presence: true
  validate :has_boundary

  def as_geojson
    {
      type: "Feature",
      id: id,
      properties: { name_th: name, level: "access_area", source: source,
                    subdistrict_ids: subdistrict_ids, subdistrict_count: subdistrict_ids.size },
      geometry: boundary && RGeo::GeoJSON.encode(boundary)
    }
  end

  private

  def has_boundary
    errors.add(:boundary, "ต้องระบุขอบเขตพื้นที่ดูแล") unless boundary.present?
  end
end

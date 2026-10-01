class UserAccessArea < ApplicationRecord
  ORGANIZATION_TYPES = {
    "subdistrict_administrative_organization" => "องค์การบริหารส่วนตำบล (อบต.)",
    "subdistrict_municipality" => "เทศบาลตำบล",
    "town_municipality" => "เทศบาลเมือง",
    "city_municipality" => "เทศบาลนคร",
    "special_local_government" => "องค์กรปกครองส่วนท้องถิ่นรูปแบบพิเศษ"
  }.freeze

  belongs_to :user

  validates :name, :source, presence: true
  validates :organization_type, inclusion: { in: ORGANIZATION_TYPES.keys }
  validate :has_boundary

  def organization_type_label
    ORGANIZATION_TYPES.fetch(organization_type, "ยังไม่ระบุประเภทองค์กร")
  end

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

class AddOrganizationTypeToUserAccessAreas < ActiveRecord::Migration[7.2]
  def up
    add_column :user_access_areas, :organization_type, :string, null: false,
      default: "subdistrict_administrative_organization"

    execute <<~SQL
      UPDATE user_access_areas
      SET organization_type = CASE
        WHEN name LIKE 'เทศบาลนคร%' THEN 'city_municipality'
        WHEN name LIKE 'เทศบาลเมือง%' THEN 'town_municipality'
        WHEN name LIKE 'เทศบาลตำบล%' THEN 'subdistrict_municipality'
        WHEN name LIKE 'กรุงเทพมหานคร%' OR name LIKE 'เมืองพัทยา%' THEN 'special_local_government'
        ELSE 'subdistrict_administrative_organization'
      END
    SQL
  end

  def down
    remove_column :user_access_areas, :organization_type
  end
end

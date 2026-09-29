class AddOrganizationKeyToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :organization_key, :string

    execute <<~SQL.squish
      UPDATE users
      SET organization_key = CASE
        WHEN role = 0 THEN 'system:' || id::text
        WHEN subdistrict_id IS NOT NULL THEN 'subdistrict:' || subdistrict_id::text
        ELSE 'account:' || id::text
      END
    SQL

    change_column_null :users, :organization_key, false
    add_index :users, :organization_key
  end

  def down
    remove_index :users, :organization_key
    remove_column :users, :organization_key
  end
end

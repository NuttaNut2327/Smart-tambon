class ExpandAdministrativeAreaMetadata < ActiveRecord::Migration[7.2]
  def up
    add_column :subdistricts, :district_code, :string unless column_exists?(:subdistricts, :district_code)
    add_column :subdistricts, :district_name_th, :string unless column_exists?(:subdistricts, :district_name_th)
    add_column :subdistricts, :district_name_en, :string unless column_exists?(:subdistricts, :district_name_en)
    add_column :subdistricts, :population, :integer unless column_exists?(:subdistricts, :population)
    add_column :subdistricts, :source_name, :string unless column_exists?(:subdistricts, :source_name)
    add_column :subdistricts, :source_date, :date unless column_exists?(:subdistricts, :source_date)
    execute <<~SQL
      ALTER TABLE provinces ALTER COLUMN boundary TYPE geography(MultiPolygon, 4326)
      USING ST_Multi(boundary::geometry)::geography
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

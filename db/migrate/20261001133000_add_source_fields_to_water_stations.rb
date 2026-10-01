class AddSourceFieldsToWaterStations < ActiveRecord::Migration[7.2]
  def change
    add_column :water_stations, :source, :string, null: false, default: "dwr"
    add_column :water_stations, :source_station_id, :string
    add_column :water_stations, :agency_name, :string
    add_column :water_stations, :water_level_source, :string
    add_column :water_stations, :rainfall_source, :string
    add_column :water_stations, :source_metadata, :jsonb, null: false, default: {}

    add_index :water_stations, %i[source source_station_id], unique: true,
      where: "source_station_id IS NOT NULL", name: "index_water_stations_on_source_identity"
  end
end

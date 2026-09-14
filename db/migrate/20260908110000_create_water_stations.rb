class CreateWaterStations < ActiveRecord::Migration[7.2]
  def change
    create_table :water_stations do |t|
      t.string :station_id, null: false
      t.string :station_code
      t.string :station_name_th
      t.string :station_name_en
      t.string :agency
      t.string :province_code
      t.string :province_name_th
      t.string :district_name_th
      t.string :subdistrict_name_th
      t.string :main_basin_code
      t.string :main_basin_name_th
      t.string :sub_basin_code
      t.string :sub_basin_name_th
      t.jsonb :equipment, null: false, default: []
      t.float :water_level_m_msl
      t.datetime :water_level_observed_at
      t.float :rainfall_value
      t.datetime :rainfall_observed_at
      t.float :flow_rate_m3_s
      t.float :river_capacity_percent
      t.datetime :source_observed_at
      t.geography :location, type: :st_point, srid: 4326, null: false
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :water_stations, :station_id, unique: true
    add_index :water_stations, :location, using: :gist
  end
end

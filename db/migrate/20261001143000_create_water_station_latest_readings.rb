class CreateWaterStationLatestReadings < ActiveRecord::Migration[7.2]
  def change
    add_column :water_stations, :canonical_station_key, :string
    add_column :water_stations, :last_seen_at, :datetime
    add_column :water_stations, :missing_sync_count, :integer, null: false, default: 0
    add_column :water_stations, :sync_status, :string, null: false, default: "online"
    add_index :water_stations, :canonical_station_key
    add_index :water_stations, %i[source sync_status]

    create_table :water_station_latest_readings do |t|
      t.references :water_station, null: false, foreign_key: true, index: { unique: true }
      t.float :water_level_m_msl
      t.datetime :water_level_observed_at
      t.string :water_level_source
      t.float :rainfall_value
      t.datetime :rainfall_observed_at
      t.string :rainfall_source
      t.float :flow_rate_m3_s
      t.float :river_capacity_percent
      t.datetime :source_observed_at
      t.string :payload_digest
      t.timestamps
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          INSERT INTO water_station_latest_readings
            (water_station_id, water_level_m_msl, water_level_observed_at, water_level_source,
             rainfall_value, rainfall_observed_at, rainfall_source, flow_rate_m3_s,
             river_capacity_percent, source_observed_at, created_at, updated_at)
          SELECT id, water_level_m_msl, water_level_observed_at, COALESCE(water_level_source, source),
                 rainfall_value, rainfall_observed_at, COALESCE(rainfall_source, source), flow_rate_m3_s,
                 river_capacity_percent, source_observed_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM water_stations
        SQL
        execute "UPDATE water_stations SET last_seen_at = COALESCE(source_observed_at, updated_at)"
      end
    end
  end
end

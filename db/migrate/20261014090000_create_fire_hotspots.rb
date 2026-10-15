class CreateFireHotspots < ActiveRecord::Migration[7.2]
  def change
    create_table :fire_hotspots do |t|
      t.string :hotspot_key, null: false
      t.string :source, null: false
      t.string :satellite
      t.string :instrument
      t.st_point :location, geographic: true, srid: 4326, null: false
      t.datetime :acquired_at, null: false
      t.float :brightness
      t.float :brightness_t31
      t.float :frp
      t.string :confidence
      t.string :daynight
      t.float :scan
      t.float :track
      t.string :version
      t.timestamps
    end

    add_index :fire_hotspots, :hotspot_key, unique: true
    add_index :fire_hotspots, :acquired_at
    add_index :fire_hotspots, :location, using: :gist
  end
end

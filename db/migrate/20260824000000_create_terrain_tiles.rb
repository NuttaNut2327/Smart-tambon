class CreateTerrainTiles < ActiveRecord::Migration[7.2]
  def change
    create_table :terrain_tiles do |t|
      t.integer :zoom_level, null: false
      t.integer :tile_x, null: false
      t.integer :tile_y, null: false
      t.binary :image_data, null: false
      t.string :source, null: false, default: "AWS Open Data Terrain Tiles"
      t.datetime :imported_at, null: false

      t.timestamps
    end

    add_index :terrain_tiles, %i[zoom_level tile_x tile_y], unique: true, name: "index_terrain_tiles_on_coordinates"
    add_check_constraint :terrain_tiles, "zoom_level BETWEEN 0 AND 15", name: "terrain_tiles_zoom_level_range"
  end
end

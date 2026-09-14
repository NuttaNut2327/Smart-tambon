class CreateUserAccessAreas < ActiveRecord::Migration[7.2]
  def change
    create_table :user_access_areas do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.string :source, null: false, default: "subdistricts"
      t.jsonb :subdistrict_ids, null: false, default: []
      t.multi_polygon :boundary, geographic: true, srid: 4326
      t.timestamps
    end

    add_index :user_access_areas, :boundary, using: :gist
  end
end

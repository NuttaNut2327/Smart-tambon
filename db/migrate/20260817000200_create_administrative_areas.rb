class CreateAdministrativeAreas < ActiveRecord::Migration[7.2]
  def change
    create_table :provinces do |t|
      t.string :code, null: false
      t.string :name_th, null: false
      t.string :name_en
      t.geography :boundary, type: :multi_polygon, srid: 4326
      t.geography :center, type: :st_point, srid: 4326
      t.timestamps
    end
    add_index :provinces, :code, unique: true
    add_index :provinces, :boundary, using: :gist

    create_table :subdistricts do |t|
      t.references :province, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name_th, null: false
      t.string :name_en
      t.string :district_code
      t.string :district_name_th
      t.string :district_name_en
      t.integer :population
      t.string :source_name
      t.date :source_date
      t.geography :boundary, type: :multi_polygon, srid: 4326
      t.geography :center, type: :st_point, srid: 4326
      t.timestamps
    end
    add_index :subdistricts, :code, unique: true
    add_index :subdistricts, :boundary, using: :gist
  end
end

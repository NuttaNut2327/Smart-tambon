class CreatePopulationDatasets < ActiveRecord::Migration[7.2]
  def change
    create_table :population_datasets do |t|
      t.references :subdistrict, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :source_file, null: false
      t.jsonb :records, null: false, default: []
      t.jsonb :summary, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
  end
end

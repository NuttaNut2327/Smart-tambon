class CreateAnalysisRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :analysis_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :subdistrict, foreign_key: true
      t.string :name, null: false
      t.string :selection_type, null: false
      t.jsonb :geometry, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.jsonb :places, null: false, default: []
      t.timestamps
    end
  end
end

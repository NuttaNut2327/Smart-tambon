class AddSharedWithAllToPopulationDatasets < ActiveRecord::Migration[7.2]
  def change
    add_column :population_datasets, :shared_with_all, :boolean, null: false, default: false
    add_index :population_datasets, :shared_with_all
  end
end

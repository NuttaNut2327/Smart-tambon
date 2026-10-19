class AddContactFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :full_name, :string
    add_column :users, :position, :string
    add_column :users, :phone, :string
    add_index :users, :phone, unique: true, where: "phone IS NOT NULL"
  end
end

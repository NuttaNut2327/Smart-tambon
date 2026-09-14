class AddUsernameToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :username, :string
    execute <<~SQL
      UPDATE users
      SET username = CASE
        WHEN role = 0 THEN 'admin'
        WHEN role = 1 THEN 'admin' || COALESCE((SELECT code FROM subdistricts WHERE subdistricts.id = users.subdistrict_id), users.id::text)
        WHEN role = 2 THEN 'user' || COALESCE((SELECT code FROM subdistricts WHERE subdistricts.id = users.subdistrict_id), users.id::text)
        ELSE 'user' || users.id::text
      END
    SQL
    change_column_null :users, :username, false
    add_index :users, :username, unique: true
  end

  def down
    remove_index :users, :username
    remove_column :users, :username
  end
end

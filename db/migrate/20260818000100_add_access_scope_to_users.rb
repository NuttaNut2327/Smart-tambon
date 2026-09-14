class AddAccessScopeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :role, :integer
    add_reference :users, :subdistrict, foreign_key: true
    add_index :users, :role

    reversible do |direction|
      direction.up do
        admin_email = ENV.fetch("ADMIN_EMAIL", "admin@smartcity.local")
        quoted_email = ActiveRecord::Base.connection.quote(admin_email)
        execute "UPDATE users SET role = 0 WHERE email = #{quoted_email}"
      end
    end
  end
end

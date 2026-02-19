class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "viewer"
      t.datetime :last_signed_in_at
      t.string :last_signed_in_ip

      t.timestamps
    end

    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
    add_index :users, :role
  end
end

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.bigint :github_id, null: false
      t.string :github_login, null: false
      t.string :github_name
      t.string :github_email
      t.string :github_avatar_url
      t.text :github_access_token_ciphertext  # Encrypted by Lockbox

      t.timestamps

      t.index :github_id, unique: true
      t.index :github_login
    end
  end
end

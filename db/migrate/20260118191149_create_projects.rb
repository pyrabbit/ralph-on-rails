class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :github_repository, null: false
      t.text :github_token_ciphertext, null: false  # Encrypted by Lockbox
      t.text :github_webhook_secret_ciphertext, null: false  # Encrypted by Lockbox
      t.text :anthropic_api_key_ciphertext, null: false  # Encrypted by Lockbox
      t.json :settings, default: {}
      t.boolean :active, default: true, null: false

      t.timestamps

      t.index :slug, unique: true
      t.index :github_repository
      t.index :active
    end
  end
end

class MakeProjectCredentialsNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :projects, :github_token_ciphertext, true
    change_column_null :projects, :github_webhook_secret_ciphertext, true
    change_column_null :projects, :anthropic_api_key_ciphertext, true
  end
end

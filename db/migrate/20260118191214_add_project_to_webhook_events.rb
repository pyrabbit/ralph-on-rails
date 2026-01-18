class AddProjectToWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :webhook_events, :project, null: false, foreign_key: true

    # Update unique constraint to be scoped by project
    remove_index :webhook_events, :delivery_id if index_exists?(:webhook_events, :delivery_id)
    add_index :webhook_events, [:project_id, :delivery_id], unique: true
  end
end

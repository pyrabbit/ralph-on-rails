# frozen_string_literal: true

class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :delivery_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.json :payload, null: false
      t.string :task_type
      t.integer :priority
      t.json :task_metadata
      t.string :processing_status, default: "pending", null: false
      t.text :processing_error
      t.datetime :processed_at

      t.timestamps
    end

    add_index :webhook_events, :event_type
    add_index :webhook_events, :processing_status
    add_index :webhook_events, :task_type
    add_index :webhook_events, :created_at
  end
end

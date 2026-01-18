# frozen_string_literal: true

class CreateMainBranchHealth < ActiveRecord::Migration[7.1]
  def change
    create_table :ralph_main_branch_health do |t|
      t.string :commit_hash, null: false
      t.boolean :tests_passing, null: false, default: false
      t.boolean :linting_passing, null: false, default: false
      t.boolean :working_directory_clean, null: false, default: false
      t.datetime :verified_at, null: false

      t.timestamps
    end

    add_index :ralph_main_branch_health, :commit_hash, unique: true
  end
end

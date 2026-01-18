# frozen_string_literal: true

class AddRunningStatusToIterations < ActiveRecord::Migration[7.0]
  def change
    # No schema changes needed - status column already exists as string
    # This migration documents that "running" is now a valid status value
    # Valid statuses: "running", "success", "failure", "no_work"
  end
end

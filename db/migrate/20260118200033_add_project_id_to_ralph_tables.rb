class AddProjectIdToRalphTables < ActiveRecord::Migration[8.1]
  def change
    # Add project_id to all Ralph tables
    ralph_tables = [
      :ralph_issue_assignments,
      :ralph_pull_requests,
      :ralph_design_documents,
      :ralph_design_doc_comments,
      :ralph_claude_sessions,
      :ralph_iterations,
      :ralph_task_queue_items,
      :ralph_main_branch_health
    ]

    ralph_tables.each do |table|
      next if column_exists?(table, :project_id)

      # Use nullable initially to allow migration, will enforce in application
      # add_reference automatically creates an index, so we don't need add_index
      add_reference table, :project, null: true, foreign_key: { to_table: :projects }
    end
  end
end

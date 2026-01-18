class AddProjectToRalphTables < ActiveRecord::Migration[8.1]
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
      if table_exists?(table)
        add_reference table, :project, null: false, foreign_key: { to_table: :projects }
        add_index table, :project_id
      end
    end
  end
end

# frozen_string_literal: true

class CreateRalphSchema < ActiveRecord::Migration[7.1]
  def change
    # Issue Assignments
    create_table :ralph_issue_assignments do |t|
      t.integer :github_issue_id, null: false
      t.integer :github_issue_number, null: false
      t.string :repository, null: false
      t.string :title
      t.text :body
      t.string :state, default: "discovered"
      t.datetime :assigned_at
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :parent_issue_id
      t.datetime :reapproval_requested_at
      t.string :conflicts_hash
      t.json :metadata

      # From migration 002: parent-child tracking
      t.integer :merge_order
      t.string :feature_branch

      # From migration 003: parent PR trigger tracking
      t.boolean :parent_pr_triggered, default: false, null: false

      t.timestamps
    end

    add_index :ralph_issue_assignments, :github_issue_id, unique: true
    add_index :ralph_issue_assignments, :state
    add_index :ralph_issue_assignments, :parent_issue_id
    add_index :ralph_issue_assignments, [:parent_issue_id, :merge_order]
    add_index :ralph_issue_assignments, :feature_branch

    # Foreign key constraint from migration 002
    add_foreign_key :ralph_issue_assignments, :ralph_issue_assignments,
      column: :parent_issue_id, on_delete: :nullify

    # Iterations
    create_table :ralph_iterations do |t|
      t.integer :iteration_number, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.boolean :work_found, default: false
      t.string :work_type
      t.integer :task_queue_item_id
      t.integer :pull_request_id
      t.string :status
      t.integer :backoff_seconds
      t.text :error_message
      t.json :metadata

      t.timestamps
    end

    add_index :ralph_iterations, :iteration_number
    add_index :ralph_iterations, :status

    # Claude Sessions
    create_table :ralph_claude_sessions do |t|
      t.integer :iteration_id
      t.text :command
      t.integer :exit_code
      t.text :output
      t.datetime :started_at
      t.datetime :completed_at
      t.string :model
      t.string :context

      t.timestamps
    end

    add_index :ralph_claude_sessions, :iteration_id
    add_index :ralph_claude_sessions, :model
    add_index :ralph_claude_sessions, :context

    # Pull Requests
    create_table :ralph_pull_requests do |t|
      t.integer :github_pr_id
      t.integer :github_pr_number
      t.string :repository, null: false
      t.integer :issue_assignment_id, null: false
      t.string :title
      t.string :state, default: "draft"
      t.string :worktree_path
      t.string :branch_name
      t.integer :line_count
      t.boolean :has_tests, default: false
      t.datetime :last_review_at
      t.integer :unresolved_comments_count, default: 0
      t.json :metadata

      # From migration 004: PR maintenance tracking
      t.datetime :last_maintenance_check_at
      t.integer :maintenance_check_count, default: 0

      # From migration 005: target branch for feature PRs
      t.string :target_branch

      t.timestamps
    end

    add_index :ralph_pull_requests, :github_pr_id, unique: true
    add_index :ralph_pull_requests, :issue_assignment_id
    add_index :ralph_pull_requests, :state

    # Task Queue Items
    create_table :ralph_task_queue_items do |t|
      t.integer :issue_assignment_id
      t.integer :pull_request_id
      t.string :work_type, null: false
      t.integer :priority, default: 10
      t.string :state, default: "queued"
      t.integer :retry_count, default: 0
      t.text :last_error
      t.json :metadata

      t.timestamps
    end

    add_index :ralph_task_queue_items, [:state, :priority, :created_at]
    add_index :ralph_task_queue_items, :work_type

    # Design Documents
    create_table :ralph_design_documents do |t|
      t.references :issue_assignment, null: false, foreign_key: {to_table: :ralph_issue_assignments}
      t.string :gist_id, null: false
      t.string :gist_url, null: false
      t.text :content, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :approved_at
      t.string :approval_type
      t.string :base_commit_hash
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :ralph_design_documents, :gist_id, unique: true
    add_index :ralph_design_documents, :status
    add_index :ralph_design_documents, :approved_at

    # Design Doc Comments
    create_table :ralph_design_doc_comments do |t|
      t.references :issue_assignment, null: false, foreign_key: {to_table: :ralph_issue_assignments}
      t.string :gist_id, null: false
      t.string :comment_id, null: false
      t.boolean :addressed, default: false, null: false
      t.datetime :addressed_at
      t.string :author
      t.text :body
      t.datetime :commented_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :ralph_design_doc_comments, [:issue_assignment_id, :gist_id, :comment_id],
      unique: true, name: "index_ralph_design_doc_comments_unique"
    add_index :ralph_design_doc_comments, :gist_id
    add_index :ralph_design_doc_comments, :resolved_at
  end
end

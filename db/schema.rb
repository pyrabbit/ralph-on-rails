# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_18_200334) do
  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.string "role", default: "viewer", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["role"], name: "index_project_memberships_on_role"
    t.index ["user_id", "project_id"], name: "index_project_memberships_on_user_id_and_project_id", unique: true
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "anthropic_api_key_ciphertext"
    t.datetime "created_at", null: false
    t.string "github_repository", null: false
    t.text "github_token_ciphertext"
    t.text "github_webhook_secret_ciphertext"
    t.string "name", null: false
    t.json "settings", default: {}
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_projects_on_active"
    t.index ["github_repository"], name: "index_projects_on_github_repository", unique: true
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "ralph_claude_sessions", force: :cascade do |t|
    t.text "command"
    t.datetime "completed_at"
    t.string "context"
    t.datetime "created_at", null: false
    t.integer "exit_code"
    t.integer "iteration_id"
    t.string "model"
    t.text "output"
    t.integer "project_id"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.index ["context"], name: "index_ralph_claude_sessions_on_context"
    t.index ["iteration_id"], name: "index_ralph_claude_sessions_on_iteration_id"
    t.index ["model"], name: "index_ralph_claude_sessions_on_model"
    t.index ["project_id"], name: "index_ralph_claude_sessions_on_project_id"
  end

  create_table "ralph_design_doc_comments", force: :cascade do |t|
    t.boolean "addressed", default: false, null: false
    t.datetime "addressed_at"
    t.string "author"
    t.text "body"
    t.string "comment_id", null: false
    t.datetime "commented_at"
    t.datetime "created_at", null: false
    t.boolean "created_by_ralph", default: false, null: false
    t.string "gist_id", null: false
    t.boolean "implemented", default: false, null: false
    t.datetime "implemented_at"
    t.integer "implemented_in_pr_number"
    t.integer "issue_assignment_id", null: false
    t.integer "project_id"
    t.datetime "resolved_at"
    t.datetime "updated_at", null: false
    t.index ["created_by_ralph"], name: "index_ralph_design_doc_comments_on_created_by_ralph"
    t.index ["gist_id"], name: "index_ralph_design_doc_comments_on_gist_id"
    t.index ["implemented"], name: "index_ralph_design_doc_comments_on_implemented"
    t.index ["issue_assignment_id", "gist_id", "comment_id"], name: "index_ralph_design_doc_comments_unique", unique: true
    t.index ["issue_assignment_id"], name: "index_ralph_design_doc_comments_on_issue_assignment_id"
    t.index ["project_id"], name: "index_ralph_design_doc_comments_on_project_id"
    t.index ["resolved_at"], name: "index_ralph_design_doc_comments_on_resolved_at"
  end

  create_table "ralph_design_documents", force: :cascade do |t|
    t.string "approval_type"
    t.datetime "approved_at"
    t.string "base_commit_hash"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "gist_id", null: false
    t.string "gist_url", null: false
    t.integer "issue_assignment_id", null: false
    t.json "metadata", default: {}
    t.integer "project_id"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_at"], name: "index_ralph_design_documents_on_approved_at"
    t.index ["gist_id"], name: "index_ralph_design_documents_on_gist_id", unique: true
    t.index ["issue_assignment_id"], name: "index_ralph_design_documents_on_issue_assignment_id"
    t.index ["project_id"], name: "index_ralph_design_documents_on_project_id"
    t.index ["status"], name: "index_ralph_design_documents_on_status"
  end

  create_table "ralph_issue_assignments", force: :cascade do |t|
    t.datetime "assigned_at"
    t.text "body"
    t.datetime "completed_at"
    t.string "conflicts_hash"
    t.datetime "created_at", null: false
    t.string "feature_branch"
    t.integer "github_issue_id", null: false
    t.integer "github_issue_number", null: false
    t.integer "merge_order"
    t.json "metadata"
    t.integer "parent_issue_id"
    t.boolean "parent_pr_triggered", default: false, null: false
    t.integer "project_id"
    t.datetime "reapproval_requested_at"
    t.string "repository", null: false
    t.datetime "started_at"
    t.string "state", default: "discovered"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["feature_branch"], name: "index_ralph_issue_assignments_on_feature_branch"
    t.index ["github_issue_id"], name: "index_ralph_issue_assignments_on_github_issue_id", unique: true
    t.index ["parent_issue_id", "merge_order"], name: "idx_on_parent_issue_id_merge_order_428e6381c4"
    t.index ["parent_issue_id"], name: "index_ralph_issue_assignments_on_parent_issue_id"
    t.index ["project_id"], name: "index_ralph_issue_assignments_on_project_id"
    t.index ["state"], name: "index_ralph_issue_assignments_on_state"
  end

  create_table "ralph_iterations", force: :cascade do |t|
    t.integer "backoff_seconds"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "iteration_number", null: false
    t.json "metadata"
    t.integer "project_id"
    t.integer "pull_request_id"
    t.datetime "started_at"
    t.string "status"
    t.integer "task_queue_item_id"
    t.datetime "updated_at", null: false
    t.boolean "work_found", default: false
    t.string "work_type"
    t.index ["iteration_number"], name: "index_ralph_iterations_on_iteration_number"
    t.index ["project_id"], name: "index_ralph_iterations_on_project_id"
    t.index ["status"], name: "index_ralph_iterations_on_status"
  end

  create_table "ralph_main_branch_health", force: :cascade do |t|
    t.string "commit_hash", null: false
    t.datetime "created_at", null: false
    t.boolean "linting_passing", default: false, null: false
    t.integer "project_id"
    t.boolean "tests_passing", default: false, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at", null: false
    t.boolean "working_directory_clean", default: false, null: false
    t.index ["commit_hash"], name: "index_ralph_main_branch_health_on_commit_hash", unique: true
    t.index ["project_id"], name: "index_ralph_main_branch_health_on_project_id"
  end

  create_table "ralph_pull_requests", force: :cascade do |t|
    t.string "branch_name"
    t.datetime "created_at", null: false
    t.integer "github_pr_id"
    t.integer "github_pr_number"
    t.boolean "has_tests", default: false
    t.integer "issue_assignment_id", null: false
    t.datetime "last_maintenance_check_at"
    t.datetime "last_review_at"
    t.integer "line_count"
    t.integer "maintenance_check_count", default: 0
    t.json "metadata"
    t.integer "project_id"
    t.string "repository", null: false
    t.string "state", default: "draft"
    t.string "target_branch"
    t.string "title"
    t.integer "unresolved_comments_count", default: 0
    t.datetime "updated_at", null: false
    t.string "worktree_path"
    t.index ["github_pr_id"], name: "index_ralph_pull_requests_on_github_pr_id", unique: true
    t.index ["issue_assignment_id"], name: "index_ralph_pull_requests_on_issue_assignment_id"
    t.index ["project_id"], name: "index_ralph_pull_requests_on_project_id"
    t.index ["state"], name: "index_ralph_pull_requests_on_state"
  end

  create_table "ralph_task_queue_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "issue_assignment_id"
    t.text "last_error"
    t.json "metadata"
    t.integer "priority", default: 10
    t.integer "project_id"
    t.integer "pull_request_id"
    t.integer "retry_count", default: 0
    t.string "state", default: "queued"
    t.datetime "updated_at", null: false
    t.string "work_type", null: false
    t.index ["project_id"], name: "index_ralph_task_queue_items_on_project_id"
    t.index ["state", "priority", "created_at"], name: "idx_on_state_priority_created_at_2caf9e6d6d"
    t.index ["work_type"], name: "index_ralph_task_queue_items_on_work_type"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "github_access_token_ciphertext"
    t.string "github_avatar_url"
    t.string "github_email"
    t.bigint "github_id", null: false
    t.string "github_login", null: false
    t.string "github_name"
    t.datetime "updated_at", null: false
    t.index ["github_id"], name: "index_users_on_github_id", unique: true
    t.index ["github_login"], name: "index_users_on_github_login"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "delivery_id", null: false
    t.string "event_type", null: false
    t.json "payload", null: false
    t.integer "priority"
    t.datetime "processed_at"
    t.text "processing_error"
    t.string "processing_status", default: "pending", null: false
    t.integer "project_id", null: false
    t.json "task_metadata"
    t.string "task_type"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
    t.index ["processing_status"], name: "index_webhook_events_on_processing_status"
    t.index ["project_id", "delivery_id"], name: "index_webhook_events_on_project_id_and_delivery_id", unique: true
    t.index ["project_id"], name: "index_webhook_events_on_project_id"
    t.index ["task_type"], name: "index_webhook_events_on_task_type"
  end

  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "ralph_claude_sessions", "projects"
  add_foreign_key "ralph_design_doc_comments", "projects"
  add_foreign_key "ralph_design_doc_comments", "ralph_issue_assignments", column: "issue_assignment_id"
  add_foreign_key "ralph_design_documents", "projects"
  add_foreign_key "ralph_design_documents", "ralph_issue_assignments", column: "issue_assignment_id"
  add_foreign_key "ralph_issue_assignments", "projects"
  add_foreign_key "ralph_issue_assignments", "ralph_issue_assignments", column: "parent_issue_id", on_delete: :nullify
  add_foreign_key "ralph_iterations", "projects"
  add_foreign_key "ralph_main_branch_health", "projects"
  add_foreign_key "ralph_pull_requests", "projects"
  add_foreign_key "ralph_task_queue_items", "projects"
  add_foreign_key "webhook_events", "projects"
end

require "test_helper"

class RalphDataIsolationTest < ActionDispatch::IntegrationTest
  def setup
    skip "Ralph tables not set up in test database yet"
    setup_all_project_credentials
  end

  test "Ralph models are automatically scoped to Current.project" do
    project1 = projects(:acme_web)
    project2 = projects(:acme_api)

    # Create issue for project1
    set_current_project(project1)
    issue1 = Ralph::IssueAssignment.create!(
      github_issue_number: 1,
      title: "Issue for Project 1",
      state: "implementing",
      repository: project1.github_repository
    )
    assert_equal project1.id, issue1.project_id

    # Create issue for project2
    set_current_project(project2)
    issue2 = Ralph::IssueAssignment.create!(
      github_issue_number: 2,
      title: "Issue for Project 2",
      state: "implementing",
      repository: project2.github_repository
    )
    assert_equal project2.id, issue2.project_id

    # Query from project1 context - should only see project1 issues
    set_current_project(project1)
    issues = Ralph::IssueAssignment.all
    assert_includes issues, issue1
    assert_not_includes issues, issue2
    assert_equal 1, issues.count

    # Query from project2 context - should only see project2 issues
    set_current_project(project2)
    issues = Ralph::IssueAssignment.all
    assert_includes issues, issue2
    assert_not_includes issues, issue1
    assert_equal 1, issues.count

    # Without current project - should see nothing
    Current.project = nil
    issues = Ralph::IssueAssignment.all
    assert_equal 0, issues.count
  end

  test "Ralph models can be queried without scoping using unscoped_by_project" do
    project1 = projects(:acme_web)
    project2 = projects(:acme_api)

    # Create issues for both projects
    set_current_project(project1)
    issue1 = Ralph::IssueAssignment.create!(
      github_issue_number: 1,
      title: "Issue 1",
      state: "implementing",
      repository: project1.github_repository
    )

    set_current_project(project2)
    issue2 = Ralph::IssueAssignment.create!(
      github_issue_number: 2,
      title: "Issue 2",
      state: "implementing",
      repository: project2.github_repository
    )

    # Query all issues across all projects
    all_issues = Ralph::IssueAssignment.unscoped_by_project do
      Ralph::IssueAssignment.unscoped.all
    end

    assert_includes all_issues, issue1
    assert_includes all_issues, issue2
    assert all_issues.count >= 2
  end

  test "RalphTaskProcessorJob sets Current.project correctly" do
    project = projects(:acme_web)

    # Enqueue job with project_id
    RalphTaskProcessorJob.perform_later(
      project_id: project.id,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: { pr_number: 42 }
    )

    # Job should set Current.project when executing
    # This is verified by the job's perform method
    assert_enqueued_jobs 1, only: RalphTaskProcessorJob

    job = enqueued_jobs.last
    assert_equal project.id, job[:args].first[:project_id]
  end

  test "webhook event creates task scoped to correct project" do
    project1 = projects(:acme_web)
    project2 = projects(:acme_api)

    delivery_id1 = "test-delivery-project1-#{Time.current.to_i}"
    delivery_id2 = "test-delivery-project2-#{Time.current.to_i}"

    # Create webhook event for project1
    GithubWebhookTaskCreator.create_task(
      project: project1,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: {
        delivery_id: delivery_id1,
        pr_number: 100
      }
    )

    # Create webhook event for project2
    GithubWebhookTaskCreator.create_task(
      project: project2,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: {
        delivery_id: delivery_id2,
        pr_number: 200
      }
    )

    # Verify webhook events are scoped to correct projects
    event1 = project1.webhook_events.find_by(delivery_id: delivery_id1)
    event2 = project2.webhook_events.find_by(delivery_id: delivery_id2)

    assert_not_nil event1
    assert_not_nil event2
    assert_equal project1.id, event1.project_id
    assert_equal project2.id, event2.project_id

    # Verify jobs were enqueued with correct project_ids
    assert_enqueued_jobs 2, only: RalphTaskProcessorJob

    job_args = enqueued_jobs.map { |j| j[:args].first }
    project_ids = job_args.map { |args| args[:project_id] }

    assert_includes project_ids, project1.id
    assert_includes project_ids, project2.id
  end

  test "duplicate webhook delivery_id is rejected per project" do
    project = projects(:acme_web)
    delivery_id = "duplicate-test-#{Time.current.to_i}"

    # First webhook should succeed
    GithubWebhookTaskCreator.create_task(
      project: project,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: {
        delivery_id: delivery_id,
        pr_number: 42
      }
    )

    # Second webhook with same delivery_id should be skipped
    assert_no_enqueued_jobs(only: RalphTaskProcessorJob) do
      GithubWebhookTaskCreator.create_task(
        project: project,
        task_type: "pr_maintenance",
        queue: :critical,
        metadata: {
          delivery_id: delivery_id,
          pr_number: 42
        }
      )
    end

    # Only one webhook event should exist
    events = project.webhook_events.where(delivery_id: delivery_id)
    assert_equal 1, events.count
  end

  test "same delivery_id can be used across different projects" do
    project1 = projects(:acme_web)
    project2 = projects(:acme_api)
    delivery_id = "same-delivery-id-#{Time.current.to_i}"

    # Create webhook for project1
    GithubWebhookTaskCreator.create_task(
      project: project1,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: {
        delivery_id: delivery_id,
        pr_number: 42
      }
    )

    # Create webhook for project2 with same delivery_id (should succeed)
    GithubWebhookTaskCreator.create_task(
      project: project2,
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: {
        delivery_id: delivery_id,
        pr_number: 43
      }
    )

    # Both events should exist
    event1 = project1.webhook_events.find_by(delivery_id: delivery_id)
    event2 = project2.webhook_events.find_by(delivery_id: delivery_id)

    assert_not_nil event1
    assert_not_nil event2
    assert_equal project1.id, event1.project_id
    assert_equal project2.id, event2.project_id
  end

  test "Ralph configuration is set per project" do
    project1 = projects(:acme_web)
    project2 = projects(:acme_api)

    # Configure for project1
    set_current_project(project1)

    assert_equal project1.github_token, Ralph.configuration.github_token
    assert_equal project1.anthropic_api_key, Ralph.configuration.claude_api_key
    assert_equal project1.github_repository, Ralph.configuration.repository

    # Configure for project2
    set_current_project(project2)

    assert_equal project2.github_token, Ralph.configuration.github_token
    assert_equal project2.anthropic_api_key, Ralph.configuration.claude_api_key
    assert_equal project2.github_repository, Ralph.configuration.repository

    # Configurations should be different
    assert_not_equal project1.github_token, project2.github_token
    assert_not_equal project1.github_repository, project2.github_repository
  end
end

# frozen_string_literal: true

# Custom error class that preserves metadata for retry
class QualityCheckError < StandardError
  attr_reader :preserved_metadata

  def initialize(message, preserved_metadata = {})
    super(message)
    @preserved_metadata = preserved_metadata
  end
end

# Minimal task object that implements TaskQueueItem interface for Orchestrator
class WebhookTask
  attr_reader :work_type, :metadata, :issue_assignment, :pull_request, :retry_count

  def initialize(work_type:, metadata:, issue_assignment: nil, pull_request: nil, retry_count: 0)
    @work_type = work_type
    @metadata = metadata.with_indifferent_access
    @issue_assignment = issue_assignment
    @pull_request = pull_request
    @retry_count = retry_count
  end

  def mark_in_progress!
    # No-op for webhook tasks (state managed by ActiveJob)
  end

  def mark_completed!
    # No-op for webhook tasks
  end

  def mark_failed!(error)
    # No-op for webhook tasks (error raised to ActiveJob)
  end

  def update!(attrs)
    # Merge attributes into metadata
    @metadata.merge!(attrs[:metadata]) if attrs[:metadata]
  end
end

class RalphTaskProcessorJob < ApplicationJob
  queue_as :critical

  # Retry configuration for quality check failures
  retry_on QualityCheckError,
    wait: :exponentially_longer,  # 3s, 18s, 83s, 258s, ...
    attempts: 7  # Max 7 retries for quality failures

  # Don't retry on other errors (fail fast for config/auth issues)
  discard_on ActiveRecord::RecordNotFound
  discard_on ArgumentError

  def perform(project_id:, task_type:, queue:, metadata:, attempt: 1)
    @project = Project.find(project_id)

    Rails.logger.info(
      "Processing #{task_type} for project #{@project.slug} (attempt #{attempt})"
    )

    # Set current project (this scopes all Ralph queries automatically)
    Current.project = @project

    # Configure Ralph with project-specific settings
    @project.configure_ralph!

    # Setup Ralph environment
    ensure_ralph_initialized

    # Create Orchestrator instance
    orchestrator = create_orchestrator

    # Route to appropriate handler based on task_type (Ralph models automatically scoped)
    result = case task_type
    when "pr_maintenance"
      handle_pr_maintenance(orchestrator, metadata, attempt)
    when "pr_review_response"
      handle_pr_review_response(orchestrator, metadata, attempt)
    when "design_approval_check"
      handle_design_approval_check(orchestrator, metadata, attempt)
    when "new_issue"
      handle_new_issue(orchestrator, metadata, attempt)
    else
      raise ArgumentError, "Unknown task type: #{task_type}"
    end

    # Check result
    if result[:success]
      Rails.logger.info("✓ Task completed successfully")
    else
      # Preserve metadata for retry
      preserved_metadata = metadata.merge(
        attempt: attempt + 1,
        worktree_path: result[:worktree_path],
        branch_name: result[:branch_name],
        quality_failures: result[:quality_failures]
      )

      # Raise error to trigger ActiveJob retry
      raise QualityCheckError.new(result[:error], preserved_metadata)
    end
  ensure
    # Always clear Current.project to prevent leakage between jobs
    Current.project = nil
  end

  # Override retry_stopped to cleanup worktree on final failure
  def retry_stopped(_error)
    Rails.logger.error("Max retries reached, cleaning up worktree if needed")
    # TODO: Add worktree cleanup logic
  end

  private

  def ensure_ralph_initialized
    # Load Ralph configuration if not already loaded
    unless defined?(Ralph)
      require_relative "../../lib/ralph"
      Ralph.logger = Rails.logger
    end
  end

  def create_orchestrator
    # Create Orchestrator with minimal options (no daemon loop)
    Ralph::Loop::Orchestrator.new(
      sleep: 0,  # Not used in single execution
      max_backoff: 0  # Not used in single execution
    )
  end

  def handle_pr_maintenance(orchestrator, metadata, attempt)
    # Find or create PullRequest record
    pr = find_or_create_pr(metadata)

    # Find or create Iteration record
    iteration = create_iteration(attempt)

    # Build minimal task object
    task = build_task_object("pr_maintenance", metadata, pr: pr)

    # Call orchestrator's PR maintenance handler
    orchestrator.send(:handle_pr_maintenance_task, task, iteration)
  end

  def handle_pr_review_response(orchestrator, metadata, attempt)
    pr = find_or_create_pr(metadata)
    iteration = create_iteration(attempt)
    task = build_task_object("pr_review_response", metadata, pr: pr)

    orchestrator.send(:handle_pr_review_task, task, iteration)
  end

  def handle_design_approval_check(orchestrator, metadata, attempt)
    issue = find_or_create_issue(metadata)
    iteration = create_iteration(attempt)
    task = build_task_object("design_approval_check", metadata, issue: issue)

    orchestrator.send(:handle_design_approval_check_task, task, iteration)
  end

  def handle_new_issue(orchestrator, metadata, attempt)
    issue = find_or_create_issue(metadata)
    iteration = create_iteration(attempt)
    task = build_task_object("new_issue", metadata, issue: issue)

    orchestrator.send(:handle_new_issue_task, task, iteration)
  end

  def find_or_create_pr(metadata)
    pr_number = metadata[:pr_number] || metadata["pr_number"]

    Ralph::PullRequest.find_or_create_by!(
      repository: Ralph.configuration.repository,
      github_pr_number: pr_number
    ) do |pr|
      pr.project = Current.project
      pr.title = metadata[:title] || metadata["title"] || "PR ##{pr_number}"
      pr.state = "open"
      pr.metadata = metadata
    end
  end

  def find_or_create_issue(metadata)
    issue_number = metadata[:issue_number] || metadata["issue_number"]

    Ralph::IssueAssignment.find_or_create_by!(
      repository: Ralph.configuration.repository,
      github_issue_number: issue_number
    ) do |issue|
      issue.project = Current.project
      issue.title = metadata[:title] || metadata["title"] || "Issue ##{issue_number}"
      issue.state = "implementing"
      issue.body = metadata[:body] || metadata["body"]
      issue.metadata = metadata
    end
  end

  def create_iteration(attempt_number)
    Ralph::Iteration.create!(
      project: Current.project,
      iteration_number: attempt_number,
      started_at: Time.current,
      status: "running"
    )
  end

  def build_task_object(work_type, metadata, issue: nil, pr: nil)
    # Build a minimal object that quacks like TaskQueueItem
    WebhookTask.new(
      work_type: work_type,
      metadata: metadata,
      issue_assignment: issue,
      pull_request: pr,
      retry_count: metadata[:attempt].to_i - 1
    )
  end
end

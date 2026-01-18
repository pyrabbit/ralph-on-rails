# frozen_string_literal: true

require "test_helper"

class RalphTaskProcessorJobTest < ActiveJob::TestCase
  setup do
    @metadata = {
      pr_number: 42,
      title: "Test PR",
      delivery_id: "test-123"
    }
  end

  test "enqueues job with correct parameters" do
    assert_enqueued_with(job: RalphTaskProcessorJob, queue: "critical") do
      RalphTaskProcessorJob.set(queue: :critical).perform_later(
        task_type: "pr_maintenance",
        queue: :critical,
        metadata: @metadata
      )
    end
  end

  test "retries on QualityCheckError with exponential backoff" do
    # Verify retry configuration exists
    retry_handler = RalphTaskProcessorJob.retry_handlers.find do |handler|
      handler.exception == QualityCheckError
    end

    assert_not_nil retry_handler, "Should have retry handler for QualityCheckError"
    assert_equal 15, retry_handler.attempts
    assert_equal :exponentially_longer, retry_handler.wait
  end

  test "discards on ArgumentError without retry" do
    discard_handler = RalphTaskProcessorJob.discard_handlers.find do |handler|
      handler.exception == ArgumentError
    end

    assert_not_nil discard_handler, "Should have discard handler for ArgumentError"
  end

  # Integration test with mocked orchestrator (requires more setup)
  # test "executes pr_maintenance task successfully" do
  #   # Mock Ralph initialization and orchestrator
  #   # Stub orchestrator.handle_pr_maintenance_task to return success
  #   # Perform job and verify success
  # end

  # Integration test for quality check failure and retry
  # test "retries on quality check failure with preserved metadata" do
  #   # Mock orchestrator to return quality failure
  #   # Verify job re-enqueues with preserved metadata (worktree path, attempt count)
  # end

  # Integration test for model creation
  # test "creates Ralph models on first execution" do
  #   # Verify IssueAssignment or PullRequest created
  #   # Verify Iteration created with correct attempt number
  # end
end

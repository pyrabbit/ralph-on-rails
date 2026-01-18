require "test_helper"

module Webhooks
  class GithubControllerTest < ActionDispatch::IntegrationTest
    def setup
      setup_all_project_credentials
      @project = projects(:acme_web)
      @payload = { action: "synchronize", pull_request: { number: 42, mergeable: false } }
      @payload_json = @payload.to_json
    end

    def generate_signature(payload, secret)
      "sha256=" + OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new('sha256'),
        secret,
        payload
      )
    end

    test "should accept webhook with valid signature" do
      signature = generate_signature(@payload_json, @project.github_webhook_secret)

      assert_enqueued_with(job: GithubWebhookProcessorJob) do
        post webhooks_github_project_path(project_id: @project.slug),
          params: @payload_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-GitHub-Event' => 'pull_request',
            'X-GitHub-Delivery' => 'test-delivery-001',
            'X-Hub-Signature-256' => signature
          }
      end

      assert_response :ok
    end

    test "should reject webhook with invalid signature" do
      invalid_signature = "sha256=invalid_signature_here"

      assert_no_enqueued_jobs(only: GithubWebhookProcessorJob) do
        post webhooks_github_project_path(project_id: @project.slug),
          params: @payload_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-GitHub-Event' => 'pull_request',
            'X-GitHub-Delivery' => 'test-delivery-002',
            'X-Hub-Signature-256' => invalid_signature
          }
      end

      assert_response :unauthorized
    end

    test "should reject webhook with missing signature" do
      assert_no_enqueued_jobs(only: GithubWebhookProcessorJob) do
        post webhooks_github_project_path(project_id: @project.slug),
          params: @payload_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-GitHub-Event' => 'pull_request',
            'X-GitHub-Delivery' => 'test-delivery-003'
          }
      end

      assert_response :unauthorized
    end

    test "should return 404 for nonexistent project" do
      signature = generate_signature(@payload_json, "any_secret")

      post webhooks_github_project_path(project_id: 'nonexistent-project'),
        params: @payload_json,
        headers: {
          'Content-Type' => 'application/json',
          'X-GitHub-Event' => 'pull_request',
          'X-GitHub-Delivery' => 'test-delivery-004',
          'X-Hub-Signature-256' => signature
        }

      assert_response :not_found
    end

    test "should reject webhook for inactive project" do
      inactive_project = projects(:inactive_project)
      setup_project_credentials(inactive_project)
      signature = generate_signature(@payload_json, inactive_project.github_webhook_secret)

      assert_no_enqueued_jobs(only: GithubWebhookProcessorJob) do
        post webhooks_github_project_path(project_id: inactive_project.slug),
          params: @payload_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-GitHub-Event' => 'pull_request',
            'X-GitHub-Delivery' => 'test-delivery-005',
            'X-Hub-Signature-256' => signature
          }
      end

      assert_response :forbidden
    end

    test "should enqueue job with correct project_id" do
      signature = generate_signature(@payload_json, @project.github_webhook_secret)

      post webhooks_github_project_path(project_id: @project.slug),
        params: @payload_json,
        headers: {
          'Content-Type' => 'application/json',
          'X-GitHub-Event' => 'pull_request',
          'X-GitHub-Delivery' => 'test-delivery-006',
          'X-Hub-Signature-256' => signature
        }

      assert_response :ok

      # Verify job was enqueued with correct arguments
      assert_enqueued_jobs 1, only: GithubWebhookProcessorJob

      job = enqueued_jobs.last
      assert_equal @project.id, job[:args].first[:project_id]
      assert_equal 'pull_request', job[:args].first[:event_type]
      assert_equal 'test-delivery-006', job[:args].first[:delivery_id]
    end

    test "should handle different event types" do
      event_types = ['pull_request', 'check_run', 'issues', 'pull_request_review_comment']

      event_types.each do |event_type|
        signature = generate_signature(@payload_json, @project.github_webhook_secret)

        post webhooks_github_project_path(project_id: @project.slug),
          params: @payload_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-GitHub-Event' => event_type,
            'X-GitHub-Delivery' => "test-delivery-#{event_type}",
            'X-Hub-Signature-256' => signature
          }

        assert_response :ok, "Should accept #{event_type} event"
      end
    end

    test "should not require CSRF token for webhooks" do
      # Webhooks should skip CSRF protection
      signature = generate_signature(@payload_json, @project.github_webhook_secret)

      # Don't include Rails CSRF token
      post webhooks_github_project_path(project_id: @project.slug),
        params: @payload_json,
        headers: {
          'Content-Type' => 'application/json',
          'X-GitHub-Event' => 'pull_request',
          'X-GitHub-Delivery' => 'test-delivery-007',
          'X-Hub-Signature-256' => signature
        }

      # Should not raise ActionController::InvalidAuthenticityToken
      assert_response :ok
    end

    test "should not require authentication for webhooks" do
      # Don't sign in
      signature = generate_signature(@payload_json, @project.github_webhook_secret)

      post webhooks_github_project_path(project_id: @project.slug),
        params: @payload_json,
        headers: {
          'Content-Type' => 'application/json',
          'X-GitHub-Event' => 'pull_request',
          'X-GitHub-Delivery' => 'test-delivery-008',
          'X-Hub-Signature-256' => signature
        }

      assert_response :ok
    end
  end
end

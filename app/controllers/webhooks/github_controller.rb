# frozen_string_literal: true

module Webhooks
  class GithubController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :require_authentication
    skip_before_action :set_current_project

    before_action :load_project
    before_action :verify_project_active
    before_action :verify_github_signature

    def create
      event_type = request.headers["X-GitHub-Event"]
      delivery_id = request.headers["X-GitHub-Delivery"]

      Rails.logger.info(
        "GitHub webhook received: project=#{@project.slug} " \
        "event=#{event_type} delivery_id=#{delivery_id}"
      )

      # Process webhook asynchronously to ensure we respond within 10 seconds
      GithubWebhookProcessorJob.perform_later(
        project_id: @project.id,
        event_type: event_type,
        delivery_id: delivery_id,
        payload: payload_body
      )

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("GitHub webhook JSON parse error: #{e.message}")
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("GitHub webhook error: #{e.message}\n#{e.backtrace.join("\n")}")
      head :internal_server_error
    end

    private

    def load_project
      @project = Project.find_by!(slug: params[:project_id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("GitHub webhook rejected: project not found (#{params[:project_id]})")
      head :not_found
    end

    def verify_project_active
      unless @project.active?
        Rails.logger.warn("GitHub webhook rejected: project inactive (#{@project.slug})")
        head :forbidden
      end
    end

    def verify_github_signature
      signature = request.headers["X-Hub-Signature-256"]

      unless signature
        Rails.logger.warn("GitHub webhook rejected: missing signature")
        head :unauthorized
        return
      end

      # Use project-specific webhook secret
      unless GithubWebhookSignatureService.valid_signature?(
        signature,
        request.body.read,
        secret: @project.github_webhook_secret
      )
        Rails.logger.warn("GitHub webhook rejected: invalid signature (project: #{@project.slug})")
        head :unauthorized
        return
      end

      # Reset body for later reads
      request.body.rewind
    end

    def payload_body
      @payload_body ||= JSON.parse(request.body.read)
    end
  end
end

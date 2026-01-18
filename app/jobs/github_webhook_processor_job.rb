# frozen_string_literal: true

class GithubWebhookProcessorJob < ApplicationJob
  queue_as :default

  def perform(project_id:, event_type:, delivery_id:, payload:)
    @project = Project.find(project_id)

    Rails.logger.info(
      "Processing webhook for project #{@project.slug}: " \
      "event=#{event_type} delivery=#{delivery_id}"
    )

    GithubWebhookEventProcessor.process(
      project: @project,
      event_type: event_type,
      delivery_id: delivery_id,
      payload: payload
    )
  rescue StandardError => e
    Rails.logger.error(
      "Failed to process webhook for project #{@project&.slug}: " \
      "#{e.message}\n#{e.backtrace.join("\n")}"
    )
    raise
  end
end

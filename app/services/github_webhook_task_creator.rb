# frozen_string_literal: true

class GithubWebhookTaskCreator
  class << self
    def create_task(project:, task_type:, queue:, metadata:)
      delivery_id = metadata[:delivery_id]

      # Check for existing webhook event with this delivery_id (scoped to project)
      webhook_event = project.webhook_events.find_by(delivery_id: delivery_id)

      if webhook_event
        Rails.logger.info(
          "Webhook event #{delivery_id} already processed for project #{project.slug}, skipping"
        )
        return
      end

      # Create webhook event record for deduplication (scoped to project)
      webhook_event = project.webhook_events.create!(
        delivery_id: delivery_id,
        event_type: metadata[:event_type] || task_type,
        payload: metadata,
        task_type: task_type,
        priority: queue_priority(queue),
        task_metadata: metadata,
        processing_status: "pending"
      )

      # Enqueue task for processing to appropriate queue (with project_id)
      RalphTaskProcessorJob.set(queue: queue).perform_later(
        project_id: project.id,
        task_type: task_type,
        queue: queue,
        metadata: metadata
      )

      # Mark as processed only after successful enqueueing
      webhook_event.mark_processed!
      Rails.logger.info(
        "Enqueued #{task_type} task to #{queue} queue for project #{project.slug} " \
        "(delivery #{delivery_id})"
      )
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info(
        "Duplicate webhook delivery #{delivery_id} for project #{project.slug}, skipping"
      )
    rescue StandardError => e
      Rails.logger.error(
        "Failed to create task for project #{project.slug}: #{e.message}"
      )
      webhook_event&.mark_failed!(e)
      raise
    end

    private

    # Map queue names to numeric priorities for database storage
    def queue_priority(queue)
      case queue.to_sym
      when :critical then 0
      when :high then 1
      when :default then 3
      when :low then 10
      else 5
      end
    end
  end
end

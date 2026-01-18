# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  belongs_to :project

  validates :delivery_id, presence: true, uniqueness: { scope: :project_id }
  validates :event_type, presence: true
  validates :processing_status, presence: true

  scope :pending, -> { where(processing_status: "pending") }
  scope :processed, -> { where(processing_status: "processed") }
  scope :failed, -> { where(processing_status: "failed") }

  def mark_processed!
    update!(processing_status: "processed", processed_at: Time.current)
  end

  def mark_failed!(error)
    update!(
      processing_status: "failed",
      processing_error: error.to_s,
      processed_at: Time.current
    )
  end
end

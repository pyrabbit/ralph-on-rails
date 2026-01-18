# frozen_string_literal: true

# GitHub Webhook Configuration
Rails.application.configure do
  # Check if webhook secret is configured
  if ENV["GITHUB_WEBHOOK_SECRET"].blank?
    Rails.logger.warn("GITHUB_WEBHOOK_SECRET not configured - webhooks will be rejected!")
    Rails.logger.warn("Set GITHUB_WEBHOOK_SECRET environment variable to enable webhook processing")
  else
    Rails.logger.info("GitHub webhooks enabled")
  end
end

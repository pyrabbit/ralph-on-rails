# frozen_string_literal: true

# Queue Priority Configuration
#
# This application uses Solid Queue with priority-based queue processing.
# Jobs are automatically routed to appropriate queues based on task urgency.
#
# Queue Processing Order (configured in config/queue.yml):
#   1. critical - Urgent tasks that block development
#   2. high - Important tasks requiring quick attention
#   3. default - Normal priority tasks
#   4. low - Nice-to-have tasks that can wait
#
# Task to Queue Mapping:
#   critical:
#     - pr_maintenance (unmergeable PRs, failed checks)
#   high:
#     - pr_review_response (respond to PR comments)
#     - new_issue (bugs labeled "help wanted")
#   default:
#     - design_approval_check (verify design approval)
#     - new_issue (enhancements labeled "help wanted")
#   low:
#     - new_issue (other issues labeled "help wanted")
#
# Configuration:
#   See config/queue.yml for Solid Queue worker configuration
#   Workers process queues in order: critical, high, default, low

Rails.application.configure do
  # Log queue configuration on startup
  Rails.logger.info("Queue priority system enabled")
  Rails.logger.info("Processing order: critical > high > default > low")
end

# GitHub Webhook Implementation Summary

This document provides an overview of the GitHub webhook handler implementation for ralph-on-rails.

## Files Created

### Controllers
- **app/controllers/webhooks/github_controller.rb**
  - Receives webhook POST requests at `/webhooks/github`
  - Verifies HMAC-SHA256 signature
  - Queues background job for async processing
  - Returns 200 OK within GitHub's 10-second timeout

### Background Jobs
- **app/jobs/github_webhook_processor_job.rb**
  - Asynchronously processes webhook events
  - Calls event processor service
  - Handles errors and logging

### Services
- **app/services/github_webhook_signature_service.rb**
  - HMAC-SHA256 signature verification
  - Uses `ActiveSupport::SecurityUtils.secure_compare` for timing-safe comparison
  - Requires `GITHUB_WEBHOOK_SECRET` environment variable

- **app/services/github_webhook_event_processor.rb**
  - Routes events to specific handlers
  - Implements event-specific logic for:
    - `pull_request` (synchronize, opened)
    - `check_run` (completed with failures)
    - `pull_request_review_comment` (created)
    - `issues` (labeled, opened)
  - Checks trigger conditions before creating tasks
  - Adds common metadata (event_type, delivery_id) to all tasks

- **app/services/github_webhook_task_creator.rb**
  - Creates tasks with deduplication
  - Attempts to write to Ralph's task queue
  - Falls back to webhook_events table if Ralph DB is read-only
  - Tracks processing status

### Models
- **app/models/webhook_event.rb**
  - Stores all webhook events for deduplication and auditing
  - Provides scopes: `pending`, `processed`, `failed`
  - Tracks processing status and errors

### Database
- **db/migrate/20260117000001_create_webhook_events.rb**
  - Creates `webhook_events` table
  - Unique index on `delivery_id` for deduplication
  - Indexes on `event_type`, `processing_status`, `task_type`, `created_at`

### Configuration
- **config/routes.rb**
  - Added POST `/webhooks/github` route

- **config/initializers/github_webhooks.rb**
  - Checks for `GITHUB_WEBHOOK_SECRET` configuration
  - Logs warnings if not configured

### Documentation
- **WEBHOOKS.md**
  - Complete setup guide
  - Event type documentation
  - Configuration instructions
  - Troubleshooting guide
  - Security best practices

## Event Processing Summary

| Event Type | Actions | Trigger Condition | Task Type | Priority |
|-----------|---------|------------------|-----------|----------|
| pull_request | synchronize, opened | mergeable == false | pr_maintenance | 0 |
| check_run | completed | conclusion == "failure" | pr_maintenance | 0 |
| pull_request_review_comment | created | Not outdated | pr_review_response | 1 |
| issues | labeled | label == "design approved" | design_approval_check | 3 |
| issues | labeled, opened | label == "help wanted" + unassigned | new_issue | 2/5/10 |

## Key Features

### 1. Security
- HMAC-SHA256 signature verification on all requests
- Timing-safe signature comparison
- Rejects requests with missing or invalid signatures

### 2. Performance
- Responds to GitHub within 10 seconds
- Asynchronous processing via background jobs
- Fast webhook endpoint with minimal processing

### 3. Reliability
- Deduplication using GitHub's `delivery_id`
- Prevents duplicate task creation on webhook retries
- Comprehensive error handling and logging

### 4. Observability
- Detailed logging at every step
- Tracks processing status (pending/processed/failed)
- Stores full payload for debugging
- Records processing errors

### 5. Flexibility
- Works with read-only Ralph database (fallback to local table)
- Can write directly to Ralph's task queue if configured
- Extensible event processing architecture

## Required Environment Variables

```bash
GITHUB_WEBHOOK_SECRET=your_secure_random_secret
GITHUB_TOKEN=your_github_token
ANTHROPIC_API_KEY=your_anthropic_key
GITHUB_REPOSITORY=owner/repo
```

## Setup Steps

1. Set environment variables
2. Run migration: `bin/rails db:migrate`
3. Configure GitHub webhook:
   - URL: `https://your-domain.com/webhooks/github`
   - Content type: `application/json`
   - Secret: Same as `GITHUB_WEBHOOK_SECRET`
   - Events: Pull requests, Check runs, Pull request review comments, Issues

## Testing

### Manual Test
```bash
# In Rails console
payload = { "action" => "opened", "pull_request" => { "number" => 1, "mergeable" => false } }
GithubWebhookEventProcessor.process(
  event_type: "pull_request",
  delivery_id: "test-#{SecureRandom.hex}",
  payload: payload
)
```

### Check Results
```ruby
# View webhook events
WebhookEvent.order(created_at: :desc).limit(10)

# View failed events
WebhookEvent.failed

# View pending events
WebhookEvent.pending
```

## Architecture Diagram

```
GitHub → POST /webhooks/github → GithubController
                                      ↓
                                 Verify Signature
                                      ↓
                              Queue Background Job
                                      ↓
                                 Return 200 OK
                                      ↓
                          GithubWebhookProcessorJob
                                      ↓
                          GithubWebhookEventProcessor
                                      ↓
                    ┌─────────────────┴─────────────────┐
                    ↓                                   ↓
            Event-Specific Logic              GithubWebhookTaskCreator
                    ↓                                   ↓
            Check Trigger Conditions          Create WebhookEvent
                    ↓                                   ↓
            Create Task                       Attempt Ralph Task Creation
                                                       ↓
                                              Mark Processed/Failed
```

## Next Steps

1. **Deploy**: Deploy the application with webhook endpoint accessible
2. **Configure**: Set up GitHub webhook in repository settings
3. **Monitor**: Watch logs and webhook_events table for activity
4. **Integrate**: Have Ralph poll `WebhookEvent.pending` if not writing directly to Ralph DB
5. **Test**: Trigger test events to verify end-to-end flow

## Troubleshooting

See WEBHOOKS.md for detailed troubleshooting guide including:
- Signature verification issues
- Missing environment variables
- Task creation problems
- Duplicate detection
- Failed event recovery

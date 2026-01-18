# GitHub Webhook Handler

This document describes the GitHub webhook integration for ralph-on-rails, which automatically creates tasks in Ralph's queue based on GitHub events.

## Overview

The webhook handler processes GitHub events and creates corresponding tasks for the Ralph autonomous software engineer system. All webhook events are:
- **Verified** using HMAC-SHA256 signatures
- **Logged** for debugging and auditing
- **Deduplicated** to prevent duplicate task creation
- **Processed asynchronously** to ensure fast response times (< 10 seconds)

## Supported Events

### 1. Pull Request Events (`pull_request`)

**Actions**: `synchronize`, `opened`
**Trigger**: When `mergeable == false`
**Task Type**: `pr_maintenance`
**Priority**: 0 (highest)

Creates a task when a PR has merge conflicts or cannot be merged.

### 2. Check Run Events (`check_run`)

**Actions**: `completed`
**Trigger**: When `conclusion == "failure"`
**Task Type**: `pr_maintenance`
**Priority**: 0 (highest)

Creates a task when tests, linting, or build checks fail.

### 3. Review Comment Events (`pull_request_review_comment`)

**Actions**: `created`
**Trigger**: New comment thread (not outdated)
**Task Type**: `pr_review_response`
**Priority**: 1

Creates a task to respond to PR review comments.

### 4. Issue Events - Design Approval (`issues`)

**Actions**: `labeled`
**Trigger**: Label `"design approved"` added
**Task Type**: `design_approval_check`
**Priority**: 3

Creates a task when an issue is marked as design approved.

### 5. Issue Events - Help Wanted (`issues`)

**Actions**: `labeled`, `opened`
**Trigger**: Label `"help wanted"` + unassigned
**Task Type**: `new_issue`
**Priority**: 2/5/10 (based on labels)

- Priority 2: Issues labeled `bug`
- Priority 5: Issues labeled `enhancement`
- Priority 10: All other issues

## Setup

### 1. Configure Environment Variables

Add the following to your `.env` file:

```bash
# GitHub webhook secret (generate a random string)
GITHUB_WEBHOOK_SECRET=your_secure_random_secret_here

# Existing required variables
GITHUB_TOKEN=your_github_token
ANTHROPIC_API_KEY=your_anthropic_key
GITHUB_REPOSITORY=owner/repo
```

To generate a secure webhook secret:
```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

### 2. Run Database Migration

```bash
bin/rails db:migrate
```

This creates the `webhook_events` table for deduplication and event logging.

### 3. Configure GitHub Webhook

1. Go to your repository settings on GitHub
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure the webhook:
   - **Payload URL**: `https://your-domain.com/webhooks/github`
   - **Content type**: `application/json`
   - **Secret**: Use the same value as `GITHUB_WEBHOOK_SECRET`
   - **Which events?**: Select individual events:
     - Pull requests
     - Check runs
     - Pull request review comments
     - Issues
   - **Active**: ✓

4. Click **Add webhook**

### 4. Verify Configuration

After adding the webhook:
1. GitHub will send a `ping` event
2. Check your Rails logs for: `GitHub webhooks enabled`
3. Trigger a test event (e.g., label an issue)
4. Check logs for: `GitHub webhook received: event=...`

## Architecture

### Request Flow

```
GitHub Event
    ↓
POST /webhooks/github
    ↓
Webhooks::GithubController
    ├─ Verify HMAC signature
    ├─ Queue background job
    └─ Return 200 OK (< 10s)
    ↓
GithubWebhookProcessorJob (async)
    ↓
GithubWebhookEventProcessor
    ├─ Parse event type
    ├─ Extract relevant fields
    └─ Check trigger conditions
    ↓
GithubWebhookTaskCreator
    ├─ Check for duplicates (delivery_id)
    ├─ Create WebhookEvent record
    ├─ Attempt to create Ralph task
    └─ Mark as processed/failed
```

### Database Tables

#### `webhook_events`

Stores all webhook events for deduplication and auditing:

| Column | Type | Description |
|--------|------|-------------|
| `delivery_id` | string | Unique GitHub delivery ID (for deduplication) |
| `event_type` | string | GitHub event type (pull_request, issues, etc.) |
| `payload` | json | Full webhook payload |
| `task_type` | string | Ralph task type created |
| `priority` | integer | Task priority |
| `task_metadata` | json | Metadata for the task |
| `processing_status` | string | `pending`, `processed`, or `failed` |
| `processing_error` | text | Error message if processing failed |
| `processed_at` | datetime | When the event was processed |

### Deduplication

Deduplication is handled using GitHub's `X-GitHub-Delivery` header:
- Each webhook delivery has a unique ID
- Events with duplicate `delivery_id` are automatically skipped
- Prevents duplicate task creation if GitHub retries delivery

## Task Creation

The webhook handler attempts to create tasks in two ways:

1. **Direct to Ralph database** (if write access is configured)
2. **Local webhook_events table** (fallback for read-only Ralph database)

If Ralph's database is read-only, webhook events are stored in the local `webhook_events` table where Ralph can poll them.

## Monitoring

### Check Webhook Status

View recent webhook events:
```ruby
WebhookEvent.order(created_at: :desc).limit(10)
```

### Check for Failed Events

```ruby
WebhookEvent.failed
```

### Reprocess Failed Events

```ruby
failed_event = WebhookEvent.failed.first
GithubWebhookProcessorJob.perform_now(
  event_type: failed_event.event_type,
  delivery_id: failed_event.delivery_id,
  payload: failed_event.payload
)
```

## Logging

All webhook activity is logged:

```
INFO  -- GitHub webhook received: event=pull_request delivery_id=abc123
INFO  -- Processing GitHub webhook: event=pull_request delivery_id=abc123
INFO  -- PR 42: action=synchronize mergeable=false
INFO  -- Created pr_maintenance task (priority 0) for delivery abc123
```

Failed events include full stack traces:
```
ERROR -- GitHub webhook error: Something went wrong
ERROR -- <full backtrace>
```

## Security

### HMAC Signature Verification

All webhooks are verified using HMAC-SHA256:
1. GitHub signs the payload with your webhook secret
2. The signature is sent in the `X-Hub-Signature-256` header
3. The server computes the expected signature
4. Signatures are compared using `ActiveSupport::SecurityUtils.secure_compare`

Requests with invalid or missing signatures are rejected with 401 Unauthorized.

### Best Practices

- **Use HTTPS**: Always use HTTPS for your webhook URL
- **Rotate secrets**: Periodically rotate your `GITHUB_WEBHOOK_SECRET`
- **Monitor failed events**: Regularly check for and investigate failed webhook events
- **Limit webhook events**: Only subscribe to events you need to process

## Troubleshooting

### Webhook Rejected: Missing Signature

**Error**: `GitHub webhook rejected: missing signature`

**Solution**: Ensure you've set a secret in GitHub webhook settings.

### Webhook Rejected: Invalid Signature

**Error**: `GitHub webhook rejected: invalid signature`

**Solutions**:
- Verify `GITHUB_WEBHOOK_SECRET` matches GitHub webhook configuration
- Check that the webhook payload hasn't been modified in transit
- Ensure you're using HTTPS (not HTTP)

### Tasks Not Being Created

**Check**:
1. Verify webhook events are being received: `WebhookEvent.count`
2. Check for failed events: `WebhookEvent.failed`
3. Review logs for processing errors
4. Verify trigger conditions are met (e.g., PR is actually unmergeable)

### Duplicate Tasks

**Note**: The system automatically prevents duplicates using `delivery_id`. If you see duplicates:
1. Check if they have different `delivery_id` values
2. GitHub may have sent separate events for the same PR (e.g., both `synchronize` and check failure)

## Testing

### Manual Testing

Trigger a test webhook from GitHub:
1. Go to **Settings** → **Webhooks** → Your webhook
2. Scroll to **Recent Deliveries**
3. Click on a delivery → **Redeliver**

### Unit Testing

Run webhook-related tests:
```bash
bin/rails test test/services/github_webhook*
bin/rails test test/controllers/webhooks/*
```

### Integration Testing

1. Create a test PR with conflicts
2. Verify webhook is received
3. Check that task is created: `WebhookEvent.where(task_type: 'pr_maintenance')`

## API for Ralph Integration

If Ralph needs to poll for pending webhook tasks:

```ruby
# Get pending webhook events
pending_events = WebhookEvent.pending.order(priority: :asc, created_at: :asc)

# Process an event
event = pending_events.first
# ... create task in Ralph system ...
event.mark_processed!
```

Alternatively, expose an API endpoint for Ralph to consume webhook events.

# Priority Queue System

This document describes how ralph-on-rails uses ActiveJob with Solid Queue to automatically manage task execution order.

## Overview

The application uses named queues to prioritize work. Tasks are automatically routed to appropriate queues, and Solid Queue processes them in priority order.

## Queue Hierarchy

Queues are processed in this order:

1. **critical** - Urgent tasks that block development
2. **high** - Important tasks requiring quick attention
3. **default** - Normal priority tasks
4. **low** - Nice-to-have tasks that can wait

## Task Queue Mapping

| Queue | Task Type | Triggered By |
|-------|-----------|--------------|
| critical | pr_maintenance | Unmergeable PRs, failed CI checks |
| high | pr_review_response | New PR review comments |
| high | new_issue | "help wanted" + "bug" labels |
| default | design_approval_check | "design approved" label |
| default | new_issue | "help wanted" + "enhancement" labels |
| low | new_issue | "help wanted" label (other) |

## How It Works

### The Flow

```
GitHub Webhook
    ↓
Webhooks::GithubController
    ↓
GithubWebhookProcessorJob (background)
    ↓
GithubWebhookEventProcessor
    ↓
Determines task_type + queue
    ↓
RalphTaskProcessorJob.set(queue: :critical).perform_later(...)
    ↓
Solid Queue processes queues in order
```

### Example: PR with Merge Conflict

```ruby
# 1. Webhook arrives
POST /webhooks/github
  payload: { action: "synchronize", pull_request: { mergeable: false } }

# 2. Event processor determines task
task_type: "pr_maintenance"
queue: :critical

# 3. Job enqueued to critical queue
RalphTaskProcessorJob.set(queue: :critical).perform_later(
  task_type: "pr_maintenance",
  queue: :critical,
  metadata: { pr_number: 42, reason: "unmergeable" }
)
```

## Configuration

### Queue Worker (config/queue.yml)

```yaml
workers:
  - queues: critical,high,default,low  # Order matters!
    threads: 3
    processes: 1
    polling_interval: 0.1
```

**The queue order determines processing priority!** Workers check queues left-to-right.

### Queue Assignment (app/services/github_webhook_event_processor.rb)

```ruby
# PR maintenance always goes to critical
create_task(
  task_type: "pr_maintenance",
  queue: :critical,
  metadata: {...}
)

# Issues route based on labels
queue = if labels.include?("bug")
  :high
elsif labels.include?("enhancement")
  :default
else
  :low
end
```

## Usage

### Enqueuing Tasks Manually

```ruby
# Enqueue directly to a queue
RalphTaskProcessorJob.set(queue: :critical).perform_later(
  task_type: "pr_maintenance",
  queue: :critical,
  metadata: { pr_number: 42 }
)
```

### Creating Tasks via Webhook Handler

```ruby
GithubWebhookTaskCreator.create_task(
  task_type: "pr_maintenance",
  queue: :critical,
  metadata: {
    pr_number: 42,
    reason: "unmergeable",
    delivery_id: "abc123"
  }
)
```

## Monitoring

### View Queue Statistics

```bash
bin/rails queue:stats
```

Output:
```
=== Queue Statistics ===

critical      3 pending jobs
high         12 pending jobs
default       5 pending jobs
low           8 pending jobs

Total pending:  28
Total running:   2
Total failed:    0
```

### View Next Jobs

```bash
bin/rails queue:next
```

Output:
```
=== Next Jobs (by queue priority) ===

CRITICAL:
  - RalphTaskProcessorJob (pr_maintenance, queue critical)
  - RalphTaskProcessorJob (pr_maintenance, queue critical)

HIGH:
  - RalphTaskProcessorJob (pr_review_response, queue high)
  - RalphTaskProcessorJob (new_issue, queue high)
```

### Retry Failed Jobs

```bash
# Retry all failed jobs
bin/rails queue:retry_failed

# Clear old failed jobs (older than 7 days)
bin/rails queue:clear_failed[7]
```

## Example Scenario

Events arrive in this order:

1. PR #100 unmergeable → **critical** queue
2. Issue #50 "help wanted" + "enhancement" → **default** queue
3. PR #99 review comment → **high** queue
4. Issue #51 "help wanted" → **low** queue
5. PR #98 CI failed → **critical** queue

### Without Priority Queues (FIFO)

```
Process Order: #100 → #50 → #99 → #51 → #98
```

❌ Critical PR #98 waits behind low-priority issue #51

### With Priority Queues

```
Process Order: #100 → #98 → #99 → #50 → #51
```

✅ Critical tasks processed first!

## Scaling

### Increase Concurrency

Adjust threads and processes:

```yaml
# config/queue.yml
workers:
  - queues: critical,high,default,low
    threads: 5  # More concurrent jobs per process
    processes: 2  # More worker processes
```

Or use environment variable:

```bash
JOB_CONCURRENCY=3 bin/rails solid_queue:start
```

### Dedicated Workers

Run separate workers for different queue groups:

```yaml
# config/queue.yml
workers:
  # Dedicated worker for critical tasks
  - queues: critical
    threads: 3
    processes: 2

  # Worker for everything else
  - queues: high,default,low
    threads: 3
    processes: 1
```

## Best Practices

### 1. Reserve Critical for True Emergencies

Only use `:critical` for:
- Broken PRs blocking CI/CD
- Failed tests preventing merges
- Security vulnerabilities

### 2. Monitor Queue Depth

Alert if queues get too deep:

```ruby
critical_count = SolidQueue::Job.where(queue_name: "critical").pending.count
alert! if critical_count > 10
```

### 3. Set SLAs by Queue

| Queue | Target Processing Time |
|-------|----------------------|
| critical | < 5 minutes |
| high | < 30 minutes |
| default | < 2 hours |
| low | < 24 hours |

### 4. Configure Retries

```ruby
class RalphTaskProcessorJob < ApplicationJob
  # Retry transient failures with backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Don't retry permanent failures
  discard_on ActiveRecord::RecordNotFound
end
```

## Troubleshooting

### Jobs Not Processing

Check if workers are running:

```bash
# Development
bin/dev

# Production
systemctl status solid_queue
```

### Wrong Queue Assignment

Check logic in `app/services/github_webhook_event_processor.rb`:

```ruby
def process_help_wanted_label(issue)
  queue = if labels.include?("bug")
    :high
  elsif labels.include?("enhancement")
    :default
  else
    :low
  end
  # ...
end
```

### Failed Jobs Building Up

```bash
# View failed jobs
SolidQueue::FailedExecution.all

# Retry all
bin/rails queue:retry_failed

# Retry specific job
SolidQueue::FailedExecution.find(123).retry
```

## Testing

### Test Queue Assignment

```ruby
test "pr_maintenance goes to critical queue" do
  assert_enqueued_with(job: RalphTaskProcessorJob, queue: "critical") do
    GithubWebhookTaskCreator.create_task(
      task_type: "pr_maintenance",
      queue: :critical,
      metadata: { delivery_id: "test-123" }
    )
  end
end
```

### Test Event Processing

```ruby
test "unmergeable PR creates critical task" do
  payload = {
    "action" => "synchronize",
    "pull_request" => { "number" => 42, "mergeable" => false }
  }

  assert_enqueued_with(job: RalphTaskProcessorJob, queue: "critical") do
    GithubWebhookEventProcessor.process(
      event_type: "pull_request",
      delivery_id: "test-123",
      payload: payload
    )
  end
end
```

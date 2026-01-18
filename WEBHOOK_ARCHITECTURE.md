# Webhook-Driven Quality Iteration Architecture

## Overview

This Rails application implements a webhook-driven architecture for Ralph's autonomous software engineering workflow. All work is triggered by GitHub webhooks rather than polling, using ActiveJob for task processing and automatic retry with quality iteration.

## Architecture

### Flow Diagram

```
GitHub Webhook → Rails Controller (verify signature, dedup)
                 ↓
                 GithubWebhookProcessorJob (async)
                 ↓
                 GithubWebhookEventProcessor (parse event)
                 ↓
                 Enqueue RalphTaskProcessorJob(task_type, metadata)
                 ↓
                 RalphTaskProcessorJob.perform
                 ├─ Create/find Ralph models (IssueAssignment, PullRequest)
                 ├─ Build task-like object for Orchestrator
                 ├─ Call Orchestrator method (handle_pr_maintenance, handle_new_issue, etc.)
                 └─ Orchestrator runs quality iteration loop:
                    ├─ Create worktree
                    ├─ Invoke Claude Code
                    ├─ Run quality checks (tests + lint)
                    ├─ If PASS: Create PR, cleanup, done
                    └─ If FAIL: Preserve worktree, raise error
                          ↓
                          ActiveJob catches error, re-enqueues
                          ↓
                          Retry with preserved worktree (loop continues)
```

## Key Components

### 1. Webhook Controller
**File:** `app/controllers/webhooks/github_controller.rb`

- Receives GitHub webhooks via POST /webhooks/github
- Verifies webhook signature using HMAC-SHA256
- Enqueues `GithubWebhookProcessorJob` for async processing
- Returns 200 OK immediately (fast response to GitHub)

### 2. Webhook Event Processor
**File:** `app/services/github_webhook_event_processor.rb`

- Parses webhook payload
- Determines task type (pr_maintenance, pr_review_response, design_approval_check, new_issue)
- Determines queue priority (critical, high, default, low)
- Delegates to task creator

### 3. Webhook Task Creator
**File:** `app/services/github_webhook_task_creator.rb`

- Creates `WebhookEvent` record for deduplication
- Enqueues `RalphTaskProcessorJob` with task metadata
- Marks webhook as processed
- No TaskQueueItems created (webhook-only architecture)

### 4. Ralph Task Processor Job
**File:** `app/jobs/ralph_task_processor_job.rb`

- **Main job** that executes Ralph work
- Creates/finds Ralph models (IssueAssignment, PullRequest, Iteration)
- Calls appropriate Orchestrator handler based on task_type
- Handles quality check failures with retry logic
- Preserves worktree metadata across retries

**Retry Configuration:**
```ruby
retry_on QualityCheckError,
  wait: :exponentially_longer,  # 3s, 18s, 83s, 258s, ...
  attempts: 15  # Max 15 retries for quality failures
```

### 5. Quality Checker (Simplified)
**File:** `lib/ralph/lib/ralph/services/quality_checker.rb`

- **Simplified to check tests + lint only**
- No line count checking (removed from quality iteration)
- Returns: `{passed:, tests_pass:, lint_pass:, has_tests:, failures:, suggestions:}`
- Line count checks can be added separately via webhook events

### 6. Orchestrator Integration
**File:** `lib/ralph/lib/ralph/loop/orchestrator.rb`

- Existing Orchestrator methods called directly from job
- Quality check handling updated to remove line count logic
- Preserves worktree on failure for retry
- Returns result hash with success/error/metadata

### 7. Work Discoverer (Deprecated)
**File:** `lib/ralph/lib/ralph/services/work_discoverer.rb`

- **Deprecated** in favor of webhook-driven architecture
- Returns `nil` (no work) to prevent GitHub polling
- Kept for backward compatibility

## Task Types

### pr_maintenance
- **Triggered by:** `pull_request` webhook (synchronize action when unmergeable)
- **Queue:** critical (priority 0)
- **Handler:** `Orchestrator#handle_pr_maintenance_task`
- **Purpose:** Fix merge conflicts, failing tests, linting errors

### pr_review_response
- **Triggered by:** `pull_request_review_comment` webhook
- **Queue:** high (priority 1)
- **Handler:** `Orchestrator#handle_pr_review_task`
- **Purpose:** Address PR review comments

### design_approval_check
- **Triggered by:** `issues` webhook (labeled with "design approved")
- **Queue:** default (priority 3)
- **Handler:** `Orchestrator#handle_design_approval_check_task`
- **Purpose:** Start implementation after design approval

### new_issue
- **Triggered by:** `issues` webhook (opened/assigned)
- **Queue:** default (priority 3, or high for bugs)
- **Handler:** `Orchestrator#handle_new_issue_task`
- **Purpose:** Create design doc and implement issue

## Quality Iteration Loop

### How It Works

1. **Job Execution:** RalphTaskProcessorJob calls Orchestrator handler
2. **Claude Code:** Orchestrator invokes Claude Code CLI to make changes
3. **Quality Check:** Run tests + lint in worktree
4. **Success Path:**
   - Tests pass ✓, Lint passes ✓
   - Create PR via gh CLI
   - Cleanup worktree
   - Job completes successfully
5. **Failure Path:**
   - Tests fail OR Lint fails
   - Preserve worktree and metadata
   - Raise `QualityCheckError`
   - ActiveJob catches error and re-enqueues (exponential backoff)
   - Retry uses preserved worktree and metadata

### Retry Metadata Preservation

When quality checks fail, the job preserves state for retry:

```ruby
{
  attempt: 2,
  worktree_path: "/tmp/ralph_worktrees/repo/issue-42",
  branch_name: "issue-42-fix-bug",
  quality_failures: {
    passed: false,
    failures: ["tests failed"],
    tests_pass: false,
    lint_pass: true,
    test_output: "...",
    lint_output: "..."
  }
}
```

On retry, the job:
- Reuses existing worktree (no re-creation)
- Increments attempt counter
- Passes failure context to Claude Code for fixing

### Max Retries

- **15 attempts** for quality failures (tests/lint)
- Exponential backoff: 3s → 18s → 83s → 258s → ...
- After max retries, worktree cleaned up (see `retry_stopped` callback)

## Database Models

### WebhookEvent (Rails app database)
- **Purpose:** Deduplication and audit trail
- **Fields:** delivery_id, event_type, payload, task_type, priority, processing_status
- **Unique constraint:** delivery_id (prevents duplicate webhook processing)

### Ralph Models (External readonly database)
- **IssueAssignment:** Issues being worked on
- **PullRequest:** PRs associated with issues
- **Iteration:** Development iteration attempts
- **DesignDocument:** Design docs for issues

**Note:** Ralph models are created by RalphTaskProcessorJob but stored in the external Ralph database.

## Deployment

### No Ralph Daemon Needed

Previously: Run `bundle exec exe/ralph start` as daemon
**Now:** Only run Rails app with Solid Queue workers

```bash
# Start Rails with Solid Queue workers
bin/dev

# Or in production with Kamal
kamal deploy
```

### Environment Variables

Required:
```bash
GITHUB_TOKEN=ghp_...
GITHUB_WEBHOOK_SECRET=...
ANTHROPIC_API_KEY=...
GITHUB_REPOSITORY=owner/repo
```

### Solid Queue Configuration

**File:** `config/queue.yml`

```yaml
workers:
  - queues: critical,high,default,low
    threads: 3
    processes: 1
    polling_interval: 0.1
```

Jobs are processed by queue priority:
- **critical:** PR maintenance (conflicts, CI failures)
- **high:** PR review responses
- **default:** Design approval checks, new issues
- **low:** Background tasks

## Webhook Configuration

### GitHub Webhook Setup

1. Go to repository Settings → Webhooks → Add webhook
2. **Payload URL:** `https://your-app.com/webhooks/github`
3. **Content type:** application/json
4. **Secret:** Set same value as `GITHUB_WEBHOOK_SECRET`
5. **Events:** Select individual events:
   - Pull requests
   - Pull request reviews
   - Pull request review comments
   - Issues
   - Issue comments

### Webhook Events Used

| Event | Actions | Purpose |
|-------|---------|---------|
| pull_request | synchronize, opened | PR maintenance when unmergeable |
| pull_request_review_comment | created | Respond to PR review |
| issues | opened, assigned, labeled | Start work on new issue, design approval |
| issue_comment | created | Respond to design doc comments (future) |

## Testing

### Unit Tests

**RalphTaskProcessorJob:**
- `test/jobs/ralph_task_processor_job_test.rb`
- Tests retry configuration
- Tests task routing
- Tests error handling

**QualityChecker:**
- `test/services/quality_checker_test.rb`
- Tests simplified quality checks (tests + lint only)
- Verifies no line count checking

### Integration Tests

**Webhook Quality Loop:**
- `test/integration/webhook_quality_loop_test.rb`
- Full webhook → retry → PR flow
- Mocked GitHub API and quality checks

### Manual Testing

```bash
# Terminal 1: Start Rails with workers
bin/dev

# Terminal 2: Send test webhook
curl -X POST http://localhost:3000/webhooks/github \
  -H "X-GitHub-Event: pull_request" \
  -H "X-GitHub-Delivery: test-$(date +%s)" \
  -H "X-Hub-Signature-256: sha256=COMPUTED_SIGNATURE" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "synchronize",
    "pull_request": {
      "number": 42,
      "title": "Test PR",
      "mergeable": false
    }
  }'

# Watch logs for:
# 1. Webhook received
# 2. Job enqueued
# 3. Orchestrator creates worktree
# 4. Claude Code runs
# 5. Quality checks run
# 6. If fail: Job retries
# 7. If pass: PR created
```

## Differences from Polling Architecture

| Aspect | Polling (Old) | Webhook (New) |
|--------|---------------|---------------|
| Work Discovery | WorkDiscoverer polls GitHub API | GitHub pushes webhook events |
| Task Queue | TaskQueueItem model + database | ActiveJob + Solid Queue |
| Retry Logic | Custom retry in Orchestrator | ActiveJob retry_on mechanism |
| Line Count | Checked in quality loop | Removed (can add as separate webhook) |
| Daemon | Ralph daemon required | Rails app + Solid Queue only |
| Latency | Poll interval (5-600s) | Instant (webhook) |
| API Calls | Continuous polling | Event-driven (fewer calls) |

## Advantages

### 1. Instant Response
- Work starts immediately when webhook received
- No waiting for next poll cycle (5-600s)

### 2. Lower API Usage
- No continuous GitHub polling
- Only fetch data when events occur
- Respects GitHub rate limits better

### 3. Simpler Deployment
- No separate Ralph daemon process
- Just Rails app with Solid Queue workers
- Easier monitoring and scaling

### 4. Better Retry Handling
- Built-in ActiveJob retry with exponential backoff
- Automatic error tracking and logging
- Configurable retry limits and strategies

### 5. Deduplication
- WebhookEvent model prevents duplicate processing
- Idempotent webhook handling
- Delivery ID tracking

## Troubleshooting

### Job Not Running

**Check Solid Queue workers:**
```bash
bin/rails solid_queue:status
```

**Check job queue:**
```ruby
# Rails console
SolidQueue::Job.where(queue_name: 'critical').count
```

### Quality Checks Always Failing

**Check test/lint configuration in Ralph:**
```bash
# In Ralph gem directory
cat config/ralph.yml
```

**Check worktree preservation:**
```bash
ls -la /tmp/ralph_worktrees/
```

### Webhook Not Received

**Check GitHub webhook deliveries:**
- Repository → Settings → Webhooks → Recent Deliveries

**Check Rails logs:**
```bash
tail -f log/development.log | grep "Webhook"
```

**Verify signature:**
- Ensure `GITHUB_WEBHOOK_SECRET` matches GitHub setting
- Check `GithubWebhookSignatureService` for signature verification

## Future Enhancements

### Line Count Webhook
- Add separate webhook event for PR size checking
- Triggered on PR ready_for_review or specific label
- Runs separate job to check line count
- Posts comment if over limit with suggestions

### Parallel Quality Checks
- Run tests and lint in parallel
- Faster feedback loop
- Requires job parallelization support

### Quality Check Caching
- Cache test results between retries
- Only re-run tests for changed files
- Faster iteration

### Progress Notifications
- Post GitHub commit status updates
- Show quality check progress in PR
- Notify on retry attempts

## References

- [Original Plan](PRIORITY_QUEUES.md) - Priority queue architecture
- [Webhook Implementation](WEBHOOK_IMPLEMENTATION.md) - Webhook setup guide
- [ActiveJob Retry](https://edgeguides.rubyonrails.org/active_job_basics.html#retrying-or-discarding-failed-jobs) - Rails docs
- [Solid Queue](https://github.com/rails/solid_queue) - Background job processor

# frozen_string_literal: true

class GithubWebhookEventProcessor
  class << self
    def process(project:, event_type:, delivery_id:, payload:)
      @project = project
      @event_type = event_type
      @delivery_id = delivery_id

      case event_type
      when "pull_request"
        process_pull_request(payload)
      when "check_run"
        process_check_run(payload)
      when "pull_request_review_comment"
        process_review_comment(payload)
      when "issues"
        process_issue(payload)
      else
        Rails.logger.debug("Ignoring webhook event type: #{event_type}")
      end
    end

    private

    attr_reader :project, :event_type, :delivery_id

    def create_task(task_type:, queue:, metadata:)
      GithubWebhookTaskCreator.create_task(
        project: project,
        task_type: task_type,
        queue: queue,
        metadata: metadata.merge(
          event_type: event_type,
          delivery_id: delivery_id
        )
      )
    end

    def process_pull_request(payload)
      action = payload["action"]
      return unless %w[synchronize opened].include?(action)

      pr = payload["pull_request"]
      pr_number = pr["number"]
      mergeable = pr["mergeable"]

      Rails.logger.info("PR #{pr_number}: action=#{action} mergeable=#{mergeable}")

      # GitHub returns mergeable as nil initially, then calculates it
      # We only create a task if it's explicitly false
      if mergeable == false
        create_task(
          task_type: "pr_maintenance",
          queue: :critical,
          metadata: {
            pr_number: pr_number,
            action: action,
            reason: "unmergeable"
          }
        )
      end
    end

    def process_check_run(payload)
      action = payload["action"]
      return unless action == "completed"

      check_run = payload["check_run"]
      conclusion = check_run["conclusion"]
      return unless conclusion == "failure"

      # Check if this is related to a PR
      pull_requests = check_run["pull_requests"] || []
      return if pull_requests.empty?

      pull_requests.each do |pr|
        pr_number = pr["number"]

        Rails.logger.info("Check run failed for PR #{pr_number}: #{check_run["name"]}")

        create_task(
          task_type: "pr_maintenance",
          queue: :critical,
          metadata: {
            pr_number: pr_number,
            check_name: check_run["name"],
            conclusion: conclusion,
            reason: "check_failure"
          }
        )
      end
    end

    def process_review_comment(payload)
      action = payload["action"]
      return unless action == "created"

      comment = payload["comment"]
      pr = payload["pull_request"]

      # Skip if comment is outdated (on old code)
      return if comment["position"].nil?

      pr_number = pr["number"]

      Rails.logger.info("New review comment on PR #{pr_number}")

      create_task(
        task_type: "pr_review_response",
        queue: :high,
        metadata: {
          pr_number: pr_number,
          comment_id: comment["id"],
          path: comment["path"],
          position: comment["position"]
        }
      )
    end

    def process_issue(payload)
      action = payload["action"]
      issue = payload["issue"]
      issue_number = issue["number"]

      # Skip if this is a PR (GitHub sends issues events for PRs too)
      return if issue["pull_request"].present?

      if action == "labeled"
        label = payload["label"]
        process_issue_labeled(issue, label)
      elsif action == "opened"
        process_issue_opened(issue)
      end
    end

    def process_issue_labeled(issue, label)
      issue_number = issue["number"]
      label_name = label["name"]

      if label_name == "design approved"
        Rails.logger.info("Issue #{issue_number} labeled 'design approved'")

        create_task(
          task_type: "design_approval_check",
          queue: :default,
          metadata: {
            issue_number: issue_number,
            label: label_name
          }
        )
      elsif label_name == "help wanted"
        process_help_wanted_label(issue)
      end
    end

    def process_issue_opened(issue)
      # Check if issue has "help wanted" label and is unassigned
      labels = issue["labels"].map { |l| l["name"] }
      return unless labels.include?("help wanted")

      process_help_wanted_label(issue)
    end

    def process_help_wanted_label(issue)
      issue_number = issue["number"]
      assignees = issue["assignees"] || []

      return unless assignees.empty?

      Rails.logger.info("Issue #{issue_number} is 'help wanted' and unassigned")

      # Queue depends on other labels
      labels = issue["labels"].map { |l| l["name"] }
      queue = if labels.include?("bug")
        :high         # Bugs are high priority
      elsif labels.include?("enhancement")
        :default      # Enhancements are normal priority
      else
        :low          # Everything else is low priority
      end

      create_task(
        task_type: "new_issue",
        queue: queue,
        metadata: {
          issue_number: issue_number,
          labels: labels
        }
      )
    end
  end
end

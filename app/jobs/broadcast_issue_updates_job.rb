class BroadcastIssueUpdatesJob < ApplicationJob
  include RalphHelper
  queue_as :default

  def perform(issue_id)
    issue = Ralph::IssueAssignment
      .includes(:design_documents, :pull_requests, :parent_issue, task_queue_items: :iterations, child_issues: [:design_documents, :pull_requests])
      .find_by(id: issue_id)

    return unless issue

    # Calculate updated metrics
    metrics = calculate_root_issue_metrics(issue)

    # Broadcast metrics dashboard update
    Turbo::StreamsChannel.broadcast_replace_to(
      "issue_#{issue_id}",
      target: "metrics_dashboard",
      partial: "ralph/issue_assignments/metrics_dashboard",
      locals: { metrics: metrics }
    )

    # Collect PR check statuses
    pr_check_statuses = {}
    issue.pull_requests.each do |pr|
      if pr.github_pr_number && pr.repository
        pr_check_statuses[pr.id] = fetch_pr_checks_status(pr.repository, pr.github_pr_number)
      end
    end

    # Broadcast header meta (PR badges in header)
    Turbo::StreamsChannel.broadcast_replace_to(
      "issue_#{issue_id}",
      target: "header_meta",
      partial: "ralph/issue_assignments/header_meta",
      locals: {
        issue: issue,
        pr_check_statuses: pr_check_statuses
      }
    )

    # Broadcast PR summary card (overview tab)
    Turbo::StreamsChannel.broadcast_replace_to(
      "issue_#{issue_id}",
      target: "pr_summary_card",
      partial: "ralph/issue_assignments/pr_summary_card",
      locals: {
        issue: issue,
        pr_check_statuses: pr_check_statuses
      }
    )

    # Broadcast full PR list (PRs tab)
    Turbo::StreamsChannel.broadcast_replace_to(
      "issue_#{issue_id}",
      target: "pr_list_full",
      partial: "ralph/issue_assignments/pr_list_full",
      locals: {
        issue: issue,
        pr_check_statuses: pr_check_statuses
      }
    )

    # Broadcast iterations list update
    iterations = issue.iterations
    Turbo::StreamsChannel.broadcast_replace_to(
      "issue_#{issue_id}",
      target: "iterations_list",
      partial: "ralph/issue_assignments/iterations_list",
      locals: { iterations: iterations }
    )

    # Schedule the next run in 10 seconds
    self.class.set(wait: 10.seconds).perform_later(issue_id)
  end
end

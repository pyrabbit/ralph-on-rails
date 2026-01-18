class BroadcastMetricsJob < ApplicationJob
  queue_as :default

  def perform
    metrics = {
      total_issues: Ralph::IssueAssignment.count,
      root_issues: Ralph::IssueAssignment.where(parent_issue_id: nil).count,
      open_prs: Ralph::PullRequest.where.not(state: "merged").count,
      design_docs: Ralph::DesignDocument.count
    }

    Turbo::StreamsChannel.broadcast_replace_to(
      "ralph_metrics",
      target: "live_metrics",
      partial: "ralph/home/metrics",
      locals: { metrics: metrics }
    )

    # Schedule the next run in 5 seconds
    self.class.set(wait: 5.seconds).perform_later
  end
end

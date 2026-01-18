module Ralph
  class PullRequest < Base
    belongs_to :issue_assignment, class_name: "Ralph::IssueAssignment"
    has_many :task_queue_items, class_name: "Ralph::TaskQueueItem", foreign_key: :pull_request_id
    has_many :iterations, class_name: "Ralph::Iteration", foreign_key: :pull_request_id

    scope :needs_attention, -> { where(state: "changes_requested").where("unresolved_comments_count > 0") }
    scope :open_prs, -> { where(state: %w[draft open changes_requested]) }
    scope :by_issue, ->(issue_id) { where(issue_assignment_id: issue_id) }

    def needs_changes?
      state == "changes_requested" && unresolved_comments_count > 0
    end

    def ready_for_review?
      state == "draft"
    end

    def approved?
      state == "approved"
    end

    def merged?
      state == "merged"
    end

    def url
      "https://github.com/#{repository}/pull/#{github_pr_number}" if github_pr_number
    end
  end
end

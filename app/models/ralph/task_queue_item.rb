module Ralph
  class TaskQueueItem < Base
    belongs_to :issue_assignment, optional: true, class_name: "Ralph::IssueAssignment"
    belongs_to :pull_request, optional: true, class_name: "Ralph::PullRequest"
    has_many :iterations, class_name: "Ralph::Iteration", foreign_key: :task_queue_item_id

    scope :pending, -> { where(state: "queued").order(priority: :asc, created_at: :asc) }
    scope :pr_work, -> { where(work_type: "pr_review_response") }
    scope :gist_comment_work, -> { where(work_type: "gist_comment_response") }
    scope :issue_work, -> { where(work_type: "new_issue") }
    scope :maintenance_work, -> { where(work_type: "pr_maintenance") }

    def queued?
      state == "queued"
    end

    def in_progress?
      state == "in_progress"
    end

    def completed?
      state == "completed"
    end

    def failed?
      state == "failed"
    end

    def retrying?
      state == "retrying"
    end
  end
end

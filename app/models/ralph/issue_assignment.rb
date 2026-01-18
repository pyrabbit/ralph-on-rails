module Ralph
  class IssueAssignment < Base
    belongs_to :parent_issue, class_name: "Ralph::IssueAssignment", optional: true, foreign_key: :parent_issue_id
    has_many :child_issues, -> { order(:merge_order) }, class_name: "Ralph::IssueAssignment", foreign_key: :parent_issue_id
    has_many :pull_requests, class_name: "Ralph::PullRequest", foreign_key: :issue_assignment_id
    has_many :task_queue_items, class_name: "Ralph::TaskQueueItem", foreign_key: :issue_assignment_id
    has_many :design_doc_comments, class_name: "Ralph::DesignDocComment", foreign_key: :issue_assignment_id
    has_many :design_documents, class_name: "Ralph::DesignDocument", foreign_key: :issue_assignment_id
    has_many :iterations, -> { order(started_at: :desc) }, through: :task_queue_items, class_name: "Ralph::Iteration"

    scope :active, -> { where(state: %w[discovered planning implementing]) }
    scope :not_started, -> { where(state: "discovered") }

    def child_issue?
      parent_issue_id.present?
    end

    def root_issue?
      parent_issue_id.nil?
    end

    def parent?
      child_issues.any?
    end

    def child?
      !parent_issue_id.nil?
    end
  end
end

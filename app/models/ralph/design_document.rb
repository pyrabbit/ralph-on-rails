module Ralph
  class DesignDocument < Base
    belongs_to :issue_assignment, class_name: "Ralph::IssueAssignment"

    scope :published, -> { where(status: "published") }
    scope :drafts, -> { where(status: "draft") }
    scope :by_issue, ->(issue_id) { where(issue_assignment_id: issue_id) }
    scope :approved, -> { where.not(approved_at: nil) }

    def self.latest_for_issue(issue_assignment_id)
      by_issue(issue_assignment_id).order(created_at: :desc).first
    end

    def draft?
      status == "draft"
    end

    def published?
      status == "published"
    end

    def approved?
      approved_at.present?
    end
  end
end

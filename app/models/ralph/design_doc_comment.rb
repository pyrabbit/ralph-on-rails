module Ralph
  class DesignDocComment < Base
    belongs_to :issue_assignment, class_name: "Ralph::IssueAssignment"
  end
end

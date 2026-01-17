module Ralph
  class HomeController < Ralph::ApplicationController
    ALLOWED_MODELS = {
      "iterations" => Ralph::Iteration,
      "claude_sessions" => Ralph::ClaudeSession,
      "issue_assignments" => Ralph::IssueAssignment,
      "pull_requests" => Ralph::PullRequest,
      "task_queue_items" => Ralph::TaskQueueItem,
      "design_documents" => Ralph::DesignDocument,
      "design_doc_comments" => Ralph::DesignDocComment,
      "main_branch_health" => Ralph::MainBranchHealth
    }.freeze

    def index
      @models = ALLOWED_MODELS.keys.sort
    end
  end
end

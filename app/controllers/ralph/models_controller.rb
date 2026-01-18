module Ralph
  class ModelsController < Ralph::ApplicationController
    include RalphHelper

    before_action :set_model_class

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
      @records = @model_class.order(created_at: :desc).limit(100)
      @model_name = params[:model_name]
    end

    def show
      @record = @model_class.find(params[:id])
      @model_name = params[:model_name]

      # Fetch CI status for Pull Requests
      if @model_class == Ralph::PullRequest && @record.github_pr_number && @record.repository
        @pr_check_status = fetch_pr_checks_status(@record.repository, @record.github_pr_number)
      end
    end

    private

    def set_model_class
      model_name = params[:model_name]
      @model_class = ALLOWED_MODELS[model_name]

      unless @model_class
        redirect_to ralph_root_path, alert: "Invalid model: #{model_name}"
      end
    end
  end
end

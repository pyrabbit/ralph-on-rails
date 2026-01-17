module Ralph
  class IssueAssignmentsController < Ralph::ApplicationController
    include RalphHelper

    def index
      @root_issues = Ralph::IssueAssignment
        .where(parent_issue_id: nil)
        .includes(:child_issues)
        .order(created_at: :desc)
    end

    def show
      @issue = Ralph::IssueAssignment
        .includes(
          :design_documents,
          :parent_issue,
          child_issues: [:design_documents, :pull_requests]
        )
        .find(params[:id])

      @active_design_doc = @issue.design_documents.order(created_at: :desc).first
      @metrics = calculate_root_issue_metrics(@issue)

      # Check if design approved label exists (only if active design doc exists)
      if @active_design_doc && @issue.github_issue_number && @issue.repository
        begin
          service = GithubLabelService.new
          @has_design_approved_label = service.has_label?(@issue.repository, @issue.github_issue_number)
          @github_available = true
        rescue Ralph::ConfigurationError => e
          # GitHub token not configured - don't show toggle
          @github_available = false
          Rails.logger.warn("GitHub token not configured: #{e.message}")
        rescue => e
          # Other errors - don't show toggle
          @github_available = false
          Rails.logger.error("Error checking GitHub label: #{e.message}")
        end
      end
    end

    def toggle_design_approved
      @issue = Ralph::IssueAssignment.find(params[:id])

      begin
        service = GithubLabelService.new
        result = service.toggle_label(@issue.repository, @issue.github_issue_number)

        if result[:success]
          @label_active = (result[:action] == :added)
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to ralph_issue_assignment_path(@issue), notice: "Label #{@label_active ? 'added' : 'removed'}" }
          end
        else
          handle_toggle_error(result[:error])
        end
      rescue Ralph::ConfigurationError => e
        handle_toggle_error("GitHub token not configured")
      rescue => e
        Rails.logger.error("Error toggling GitHub label: #{e.message}")
        handle_toggle_error("An unexpected error occurred")
      end
    end

    private

    def handle_toggle_error(error_message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "design_approval_frame",
            html: "<div class='status-message error'>#{error_message}</div>"
          )
        end
        format.html do
          redirect_to ralph_issue_assignment_path(@issue), alert: "Error: #{error_message}"
        end
      end
    end
  end
end

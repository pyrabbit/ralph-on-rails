# frozen_string_literal: true

module ProjectScoping
  extend ActiveSupport::Concern

  included do
    before_action :set_current_project, if: -> { params[:project_id] }
  end

  private

  def set_current_project
    Current.project = Project.find_by!(slug: params[:project_id])
    authorize_project_access!
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found"
  end
end

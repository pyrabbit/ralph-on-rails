# frozen_string_literal: true

class ProjectsController < ApplicationController
  skip_before_action :set_current_project
  before_action :load_project, only: [:show, :edit, :update, :destroy, :webhook_info]
  before_action -> { authorize_project_access!(:owner) }, only: [:edit, :update, :destroy]

  def index
    @projects = Current.user.projects.order(created_at: :desc)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      # Make current user the owner
      @project.project_memberships.create!(
        user: Current.user,
        role: 'owner'
      )

      redirect_to project_path(@project), notice: "Project created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    Current.project = @project
    authorize_project_access!
  end

  def edit
    Current.project = @project
  end

  def update
    Current.project = @project

    if @project.update(project_update_params)
      redirect_to project_path(@project), notice: "Project updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    Current.project = @project
    @project.destroy
    redirect_to projects_path, notice: "Project deleted successfully"
  end

  def webhook_info
    Current.project = @project
    authorize_project_access!(:member)
  end

  private

  def load_project
    @project = Project.find_by!(slug: params[:project_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to projects_path, alert: "Project not found"
  end

  def project_params
    params.require(:project).permit(
      :name,
      :github_repository,
      :github_token,
      :anthropic_api_key
    )
  end

  def project_update_params
    params.require(:project).permit(
      :name,
      :active
    )
  end
end

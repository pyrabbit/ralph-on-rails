# Multi-Project Support Implementation Plan

## Executive Summary

Transform ralph-on-rails from a single-repository viewer into a multi-tenant application supporting multiple GitHub repositories as independent Ralph projects with user authentication and authorization.

**Key Features:**
- Multiple Git repositories as independent Ralph projects
- GitHub OAuth authentication for users
- Project-based authorization (owners, members, viewers)
- UI for creating and managing Ralph projects
- Project-scoped webhooks and job execution
- Per-project Ralph configuration (tokens, API keys)

**Architecture:** Single database with project_id scoping (simpler than multiple databases)

**Clean Slate Approach:** Since we're not in production, we can reset the database and start fresh with the new multi-tenant schema. No data migration or backward compatibility needed! 🎉

## Current Architecture

**Single-tenant setup:**
- Hardcoded Ralph database connection
- Single GitHub repository: `ENV["GITHUB_REPOSITORY"]`
- Single GitHub token: `ENV["GITHUB_TOKEN"]`
- Single webhook secret: `ENV["GITHUB_WEBHOOK_SECRET"]`
- Single webhook endpoint: `/webhooks/github`
- No user authentication or authorization

## Proposed Architecture

### Multi-Tenancy Strategy

**Approach: Single Database with Project Scoping**

All Ralph data will be stored in a single database with `project_id` foreign keys:
- Store project metadata in the primary database (users, projects, memberships)
- Add `project_id` column to all Ralph tables
- Use Rails `default_scope` to automatically scope all queries by project
- Set `Current.project` during request/job execution
- Route webhook events to correct project
- Initialize Ralph configuration per-project at runtime

**Benefits over multiple databases:**
- Simpler connection management (no dynamic switching)
- Standard Rails associations and scoping
- Easier queries across projects (for admin features)
- Simpler backup/restore (one database)
- Better test isolation
- No database path configuration needed

**Safety measures:**
- Automatic project scoping via `default_scope`
- `belongs_to :project` validation on all Ralph models
- Current.project guard in Ralph::Base
- Authorization checks on every controller action

### Database Schema

#### New Models

**1. User Model** (Primary database)
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships

  # GitHub OAuth fields
  # - github_id (integer, unique, not null)
  # - github_login (string, not null)
  # - github_name (string)
  # - github_email (string)
  # - github_avatar_url (string)
  # - github_access_token (encrypted, for API calls on user's behalf)
  # - created_at, updated_at

  validates :github_id, presence: true, uniqueness: true
  validates :github_login, presence: true

  def self.find_or_create_from_github(auth)
    find_or_create_by(github_id: auth['uid']) do |user|
      user.github_login = auth['info']['nickname']
      user.github_name = auth['info']['name']
      user.github_email = auth['info']['email']
      user.github_avatar_url = auth['info']['image']
      user.github_access_token = auth['credentials']['token']
    end
  end
end
```

**2. Project Model** (Primary database)
```ruby
# app/models/project.rb
class Project < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
  has_many :webhook_events, dependent: :destroy

  # Ralph associations (will have project_id foreign key)
  has_many :issue_assignments, class_name: 'Ralph::IssueAssignment', dependent: :destroy
  has_many :pull_requests, class_name: 'Ralph::PullRequest', dependent: :destroy
  has_many :design_documents, class_name: 'Ralph::DesignDocument', dependent: :destroy

  # Fields:
  # - name (string, not null) - Human-readable name
  # - slug (string, unique, not null) - URL-safe identifier
  # - github_repository (string, not null) - "owner/repo"
  # - github_token (encrypted, not null) - Bot token for this repo
  # - github_webhook_secret (encrypted, not null) - Webhook signature verification
  # - anthropic_api_key (encrypted, not null) - Claude API key
  # - settings (jsonb) - Additional configuration
  # - active (boolean, default: true) - Enable/disable project
  # - created_at, updated_at

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :github_repository, presence: true, format: { with: /\A[\w-]+\/[\w-]+\z/ }
  validates :github_token, presence: true
  validates :github_webhook_secret, presence: true
  validates :anthropic_api_key, presence: true

  before_validation :generate_slug, on: :create
  after_create :generate_webhook_secret, unless: :github_webhook_secret?

  encrypts :github_token
  encrypts :github_webhook_secret
  encrypts :anthropic_api_key

  def owner
    project_memberships.find_by(role: 'owner')&.user
  end

  def configure_ralph!
    Ralph.configure do |config|
      config.github_token = github_token
      config.claude_api_key = anthropic_api_key
      config.repository = github_repository
    end
  end

  def issue_assignments_count
    @issue_assignments_count ||= issue_assignments.count
  end

  def pull_requests_count
    @pull_requests_count ||= pull_requests.count
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.parameterize
    candidate = base_slug
    counter = 1

    while Project.exists?(slug: candidate)
      candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate
  end

  def generate_webhook_secret
    self.github_webhook_secret = SecureRandom.hex(32)
    save
  end
end
```

**3. ProjectMembership Model** (Primary database)
```ruby
# app/models/project_membership.rb
class ProjectMembership < ApplicationRecord
  belongs_to :user
  belongs_to :project

  # Fields:
  # - user_id (bigint, not null, foreign key)
  # - project_id (bigint, not null, foreign key)
  # - role (string, not null) - 'owner', 'member', 'viewer'
  # - created_at, updated_at

  enum role: {
    owner: 'owner',     # Full access, can delete project, manage members
    member: 'member',   # Can trigger actions, view all data
    viewer: 'viewer'    # Read-only access
  }

  validates :user_id, uniqueness: { scope: :project_id }
  validates :role, presence: true, inclusion: { in: roles.keys }

  # Ensure exactly one owner per project
  validate :only_one_owner_per_project, if: :owner?

  private

  def only_one_owner_per_project
    if project.project_memberships.where(role: 'owner').where.not(id: id).exists?
      errors.add(:role, 'project can only have one owner')
    end
  end
end
```

#### Updated Models

**WebhookEvent Model** (Add project association)
```ruby
# app/models/webhook_event.rb
class WebhookEvent < ApplicationRecord
  belongs_to :project

  # Add project_id column to webhook_events table
  # Update unique constraint: delivery_id scoped to project_id

  validates :delivery_id, uniqueness: { scope: :project_id }
end
```

**Ralph::Base** (Add project scoping)
```ruby
# app/models/ralph/base.rb
module Ralph
  class Base < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = "ralph_"

    # All Ralph models belong to a project
    belongs_to :project

    # Automatically scope all queries to current project
    default_scope { where(project_id: Current.project&.id) if Current.project }

    # Make records readonly (Ralph data is managed by Ralph gem)
    def readonly?
      true
    end

    # Temporarily disable project scoping (use with caution!)
    def self.unscoped_by_project
      unscoped { yield }
    end
  end
end
```

**All Ralph Models** (Add project_id)

Every Ralph model inherits from Ralph::Base and automatically gets:
- `belongs_to :project` association
- `project_id` foreign key column (added via migration)
- Automatic scoping to `Current.project`

Models to update:
- `Ralph::IssueAssignment`
- `Ralph::PullRequest`
- `Ralph::DesignDocument`
- `Ralph::DesignDocComment`
- `Ralph::ClaudeSession`
- `Ralph::Iteration`
- `Ralph::TaskQueueItem`
- `Ralph::MainBranchHealth`

No code changes needed in individual models - just inherit from Ralph::Base!

### Authentication & Authorization

#### GitHub OAuth (OmniAuth)

**Gems to add:**
```ruby
# Gemfile
gem 'omniauth-github', '~> 2.0'
gem 'omniauth-rails_csrf_protection', '~> 1.0'
gem 'lockbox'  # For encrypting sensitive project data
gem 'blind_index'  # For searching encrypted data
```

**OmniAuth configuration:**
```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
    ENV['GITHUB_OAUTH_CLIENT_ID'],
    ENV['GITHUB_OAUTH_CLIENT_SECRET'],
    scope: 'user:email,read:org'
end
```

**Lockbox configuration:**
```ruby
# config/initializers/lockbox.rb
Lockbox.master_key = ENV["LOCKBOX_MASTER_KEY"]
```

**SessionsController:**
```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create, :failure]

  def new
    # Login page with "Sign in with GitHub" button
  end

  def create
    # OmniAuth callback
    auth = request.env['omniauth.auth']
    user = User.find_or_create_from_github(auth)

    session[:user_id] = user.id
    redirect_to projects_path, notice: "Signed in as #{user.github_login}"
  end

  def destroy
    session[:user_id] = nil
    Current.user = nil
    redirect_to root_path, notice: "Signed out"
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message]}"
  end
end
```

**Authentication Concern:**
```ruby
# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
  end

  private

  def set_current_user
    if session[:user_id]
      Current.user = User.find_by(id: session[:user_id])
    end
  end

  def require_authentication
    unless Current.user
      redirect_to login_path, alert: "Please sign in to continue"
    end
  end

  def authenticated?
    Current.user.present?
  end
end
```

**ApplicationController:**
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include ProjectScoping

  before_action :require_authentication
  before_action :set_current_project, if: :authenticated?

  # Allow unauthenticated access to static pages
  skip_before_action :require_authentication, only: [:home]

  private

  def home
    if authenticated?
      redirect_to projects_path
    else
      render 'pages/home'
    end
  end
end
```

**Authorization Concern:**
```ruby
# app/controllers/concerns/authorization.rb
module Authorization
  extend ActiveSupport::Concern

  class NotAuthorizedError < StandardError; end

  included do
    rescue_from NotAuthorizedError, with: :handle_unauthorized
  end

  private

  def authorize_project_access!(required_role = :viewer)
    unless can_access_project?(Current.project, required_role)
      raise NotAuthorizedError
    end
  end

  def can_access_project?(project, required_role = :viewer)
    return false unless Current.user
    return false unless project

    membership = project.project_memberships.find_by(user: Current.user)
    return false unless membership

    role_hierarchy = { viewer: 0, member: 1, owner: 2 }
    role_hierarchy[membership.role.to_sym] >= role_hierarchy[required_role]
  end

  def current_membership
    @current_membership ||= Current.project&.project_memberships&.find_by(user: Current.user)
  end

  def can_manage_project?
    current_membership&.owner?
  end

  def can_modify_project?
    current_membership&.owner? || current_membership&.member?
  end

  def handle_unauthorized
    redirect_to projects_path, alert: "You don't have permission to access this project"
  end
end
```

**ProjectScoping Concern:**
```ruby
# app/controllers/concerns/project_scoping.rb
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
```

**Current Attributes:**
```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :project

  def user=(user)
    super
    Time.zone = user&.time_zone if user&.time_zone
  end

  def project=(project)
    super
    # Configure Ralph when project is set
    project&.configure_ralph!
  end
end
```

### User Interface

#### Route Structure

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Root
  root to: 'application#home'

  # Authentication
  get 'login', to: 'sessions#new'
  get 'auth/github/callback', to: 'sessions#create'
  post 'auth/github/callback', to: 'sessions#create' # POST for CSRF protection
  get 'auth/failure', to: 'sessions#failure'
  delete 'logout', to: 'sessions#destroy'

  # Projects management (not scoped to specific project)
  resources :projects, only: [:index, :new, :create]

  # Project-scoped routes
  scope ':project_id' do
    # Project settings and management
    resource :project, only: [:show, :edit, :update, :destroy], controller: 'projects' do
      resources :members, only: [:index, :create, :destroy], controller: 'project_members'
      get 'webhook', to: 'projects#webhook_info'
    end

    # Ralph data viewers (existing routes, now project-scoped)
    namespace :ralph do
      root to: 'home#index'
      resources :issue_assignments, only: [:index, :show] do
        member do
          post :toggle_design_approved
        end
      end
      resources :models, only: [:index, :show]
    end
  end

  # Webhooks (project-specific, not authenticated)
  namespace :webhooks do
    post 'github/:project_id', to: 'github#create', as: :github_project
  end

  # Health check
  get "up", to: "rails/health#show", as: :rails_health_check
end
```

#### ProjectsController

```ruby
# app/controllers/projects_controller.rb
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
```

#### Views

**Projects Index**
```erb
<!-- app/views/projects/index.html.erb -->
<div class="projects-dashboard">
  <header>
    <h1>Your Ralph Projects</h1>
    <%= link_to "New Project", new_project_path, class: "btn btn-primary" %>
  </header>

  <% if @projects.any? %>
    <div class="projects-grid">
      <% @projects.each do |project| %>
        <div class="project-card">
          <h2><%= link_to project.name, project_ralph_root_path(project) %></h2>
          <p class="repo">
            <svg class="icon"><use xlink:href="#icon-github"/></svg>
            <%= project.github_repository %>
          </p>
          <div class="stats">
            <span><%= pluralize(project.issue_assignments_count, 'issue') %></span>
            <span><%= pluralize(project.pull_requests_count, 'PR') %></span>
          </div>
          <div class="status">
            <% if project.active? %>
              <span class="badge badge-success">Active</span>
            <% else %>
              <span class="badge badge-secondary">Inactive</span>
            <% end %>
          </div>
          <div class="actions">
            <%= link_to "View", project_ralph_root_path(project), class: "btn btn-sm" %>
            <% if can_manage_project_for?(project) %>
              <%= link_to "Settings", edit_project_path(project), class: "btn btn-sm btn-secondary" %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <div class="empty-state">
      <svg class="icon-large"><use xlink:href="#icon-folder"/></svg>
      <h2>No projects yet</h2>
      <p>Create your first Ralph project to get started with autonomous software engineering.</p>
      <%= link_to "Create Project", new_project_path, class: "btn btn-primary btn-large" %>
    </div>
  <% end %>
</div>
```

**Project Creation Form**
```erb
<!-- app/views/projects/new.html.erb -->
<div class="container-narrow">
  <h1>Create New Ralph Project</h1>

  <%= form_with model: @project, url: projects_path, class: "form" do |f| %>
    <% if @project.errors.any? %>
      <div class="alert alert-error">
        <h3><%= pluralize(@project.errors.count, "error") %> prevented this project from being saved:</h3>
        <ul>
          <% @project.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="form-group">
      <%= f.label :name, "Project Name" %>
      <%= f.text_field :name,
          placeholder: "My Awesome Project",
          required: true,
          class: "form-control" %>
      <p class="form-help">A human-readable name for your project</p>
    </div>

    <div class="form-group">
      <%= f.label :github_repository, "GitHub Repository" %>
      <%= f.text_field :github_repository,
          placeholder: "owner/repository",
          required: true,
          pattern: "[\\w-]+/[\\w-]+",
          class: "form-control" %>
      <p class="form-help">
        Format: <code>owner/repository</code> (e.g., <code>rails/rails</code>)
      </p>
    </div>

    <div class="form-group">
      <%= f.label :github_token, "GitHub Token" %>
      <%= f.password_field :github_token,
          required: true,
          class: "form-control",
          autocomplete: "off" %>
      <p class="form-help">
        Personal access token with <code>repo</code> and <code>workflow</code> scopes.
        <%= link_to "Create token →", "https://github.com/settings/tokens/new", target: "_blank", rel: "noopener" %>
      </p>
    </div>

    <div class="form-group">
      <%= f.label :anthropic_api_key, "Anthropic API Key" %>
      <%= f.password_field :anthropic_api_key,
          required: true,
          class: "form-control",
          autocomplete: "off" %>
      <p class="form-help">
        Your Claude API key from Anthropic.
        <%= link_to "Get API key →", "https://console.anthropic.com/", target: "_blank", rel: "noopener" %>
      </p>
    </div>

    <div class="form-actions">
      <%= f.submit "Create Project", class: "btn btn-primary" %>
      <%= link_to "Cancel", projects_path, class: "btn btn-secondary" %>
    </div>
  <% end %>
</div>
```

### Webhook Handling

**Updated GithubController** (Project-scoped)
```ruby
# app/controllers/webhooks/github_controller.rb
module Webhooks
  class GithubController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :require_authentication
    skip_before_action :set_current_project

    before_action :load_project
    before_action :verify_project_active
    before_action :verify_github_signature

    def create
      event_type = request.headers["X-GitHub-Event"]
      delivery_id = request.headers["X-GitHub-Delivery"]

      Rails.logger.info(
        "GitHub webhook received: project=#{@project.slug} " \
        "event=#{event_type} delivery_id=#{delivery_id}"
      )

      # Process webhook asynchronously
      GithubWebhookProcessorJob.perform_later(
        project_id: @project.id,
        event_type: event_type,
        delivery_id: delivery_id,
        payload: payload_body
      )

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("GitHub webhook JSON parse error: #{e.message}")
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("GitHub webhook error: #{e.message}\n#{e.backtrace.join("\n")}")
      head :internal_server_error
    end

    private

    def load_project
      @project = Project.find_by!(slug: params[:project_id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("GitHub webhook rejected: project not found (#{params[:project_id]})")
      head :not_found
    end

    def verify_project_active
      unless @project.active?
        Rails.logger.warn("GitHub webhook rejected: project inactive (#{@project.slug})")
        head :forbidden
      end
    end

    def verify_github_signature
      signature = request.headers["X-Hub-Signature-256"]

      unless signature
        Rails.logger.warn("GitHub webhook rejected: missing signature")
        head :unauthorized
        return
      end

      # Use project-specific webhook secret
      unless GithubWebhookSignatureService.valid_signature?(
        signature,
        request.body.read,
        secret: @project.github_webhook_secret
      )
        Rails.logger.warn("GitHub webhook rejected: invalid signature (project: #{@project.slug})")
        head :unauthorized
        return
      end

      request.body.rewind
    end

    def payload_body
      @payload_body ||= JSON.parse(request.body.read)
    end
  end
end
```

### Job Updates

**Updated RalphTaskProcessorJob** (Project-scoped)
```ruby
# app/jobs/ralph_task_processor_job.rb
class RalphTaskProcessorJob < ApplicationJob
  queue_as :default

  retry_on QualityCheckError,
    wait: :exponentially_longer,
    attempts: 15

  discard_on ActiveRecord::RecordNotFound
  discard_on ArgumentError

  def perform(project_id:, task_type:, queue:, metadata:, attempt: 1)
    @project = Project.find(project_id)

    Rails.logger.info(
      "Processing #{task_type} for project #{@project.slug} (attempt #{attempt})"
    )

    # Set current project (this scopes all Ralph queries automatically)
    Current.project = @project

    # Configure Ralph with project-specific settings
    @project.configure_ralph!

    # Setup Ralph environment
    ensure_ralph_initialized

    # Create Orchestrator instance
    orchestrator = create_orchestrator

    # Execute work (Ralph models automatically scoped to @project)
    result = execute_task(orchestrator, task_type, metadata, attempt)

    # Check result
    if result[:success]
      Rails.logger.info("✓ Task completed successfully for project #{@project.slug}")
    else
      # Preserve metadata for retry
      preserved_metadata = metadata.merge(
        attempt: attempt + 1,
        worktree_path: result[:worktree_path],
        branch_name: result[:branch_name],
        quality_failures: result[:quality_failures]
      )

      raise QualityCheckError.new(result[:error], preserved_metadata)
    end
  ensure
    # Clear current project
    Current.project = nil
  end

  private

  def execute_task(orchestrator, task_type, metadata, attempt)
    case task_type
    when "pr_maintenance"
      handle_pr_maintenance(orchestrator, metadata, attempt)
    when "pr_review_response"
      handle_pr_review_response(orchestrator, metadata, attempt)
    when "design_approval_check"
      handle_design_approval_check(orchestrator, metadata, attempt)
    when "new_issue"
      handle_new_issue(orchestrator, metadata, attempt)
    else
      raise ArgumentError, "Unknown task type: #{task_type}"
    end
  end

  def handle_pr_maintenance(orchestrator, metadata, attempt)
    # Find or create PullRequest record (automatically scoped to Current.project)
    pr = find_or_create_pr(metadata)
    iteration = create_iteration(attempt)
    task = build_task_object("pr_maintenance", metadata, pr: pr)

    orchestrator.send(:handle_pr_maintenance_task, task, iteration)
  end

  # ... other handler methods remain the same ...
  # Ralph models automatically scoped to Current.project via default_scope

  def find_or_create_pr(metadata)
    pr_number = metadata[:pr_number] || metadata["pr_number"]

    # Automatically scoped to Current.project
    Ralph::PullRequest.find_or_create_by!(
      github_pr_number: pr_number
    ) do |pr|
      pr.project = Current.project  # Explicit assignment
      pr.repository = Ralph.configuration.repository
      pr.title = metadata[:title] || metadata["title"] || "PR ##{pr_number}"
      pr.state = "open"
      pr.metadata = metadata
    end
  end

  def find_or_create_issue(metadata)
    issue_number = metadata[:issue_number] || metadata["issue_number"]

    # Automatically scoped to Current.project
    Ralph::IssueAssignment.find_or_create_by!(
      github_issue_number: issue_number
    ) do |issue|
      issue.project = Current.project  # Explicit assignment
      issue.repository = Ralph.configuration.repository
      issue.title = metadata[:title] || metadata["title"] || "Issue ##{issue_number}"
      issue.state = "implementing"
      issue.body = metadata[:body] || metadata["body"]
      issue.metadata = metadata
    end
  end

  def create_iteration(attempt_number)
    Ralph::Iteration.create!(
      project: Current.project,  # Explicit assignment
      iteration_number: attempt_number,
      started_at: Time.current,
      status: "running"
    )
  end

  # ... rest of methods remain the same ...
end
```

## Implementation Phases

### Phase 1: Database Setup & Models

**Approach: Fresh Start (No Data Migration)**

Since we're not in production, we can reset the database and start fresh with the new schema. This eliminates all backward compatibility complexity!

**Tasks:**
1. Add authentication and encryption gems
2. Create migrations:
   - `users` table
   - `projects` table
   - `project_memberships` table
   - Add `project_id` to `webhook_events` table
   - Add `project_id` to all Ralph tables
3. Create models: User, Project, ProjectMembership, Current
4. Update WebhookEvent model with project association
5. Update Ralph::Base with project scoping
6. Run `bin/rails db:reset` to apply new schema

**Migrations:**

```ruby
# db/migrate/XXXXXX_create_users.rb
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.bigint :github_id, null: false
      t.string :github_login, null: false
      t.string :github_name
      t.string :github_email
      t.string :github_avatar_url
      t.text :github_access_token_ciphertext  # Encrypted

      t.timestamps

      t.index :github_id, unique: true
      t.index :github_login
    end
  end
end

# db/migrate/XXXXXX_create_projects.rb
class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :github_repository, null: false
      t.text :github_token_ciphertext, null: false  # Encrypted
      t.text :github_webhook_secret_ciphertext, null: false  # Encrypted
      t.text :anthropic_api_key_ciphertext, null: false  # Encrypted
      t.jsonb :settings, default: {}
      t.boolean :active, default: true, null: false

      t.timestamps

      t.index :slug, unique: true
      t.index :github_repository
      t.index :active
    end
  end
end

# db/migrate/XXXXXX_create_project_memberships.rb
class CreateProjectMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :project_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :role, null: false, default: 'viewer'

      t.timestamps

      t.index [:user_id, :project_id], unique: true
      t.index :role
    end
  end
end

# db/migrate/XXXXXX_add_project_to_webhook_events.rb
class AddProjectToWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :webhook_events, :project, null: false, foreign_key: true

    # Update unique constraint to be scoped by project
    remove_index :webhook_events, :delivery_id
    add_index :webhook_events, [:project_id, :delivery_id], unique: true
  end
end

# db/migrate/XXXXXX_add_project_to_ralph_tables.rb
class AddProjectToRalphTables < ActiveRecord::Migration[8.0]
  def change
    # Add project_id to all Ralph tables
    [
      :ralph_issue_assignments,
      :ralph_pull_requests,
      :ralph_design_documents,
      :ralph_design_doc_comments,
      :ralph_claude_sessions,
      :ralph_iterations,
      :ralph_task_queue_items,
      :ralph_main_branch_healths
    ].each do |table|
      add_reference table, :project, null: false, foreign_key: { to_table: :projects }
      add_index table, :project_id
    end
  end
end
```

**Files to create:**
- `db/migrate/XXXXXX_create_users.rb`
- `db/migrate/XXXXXX_create_projects.rb`
- `db/migrate/XXXXXX_create_project_memberships.rb`
- `db/migrate/XXXXXX_add_project_to_webhook_events.rb`
- `db/migrate/XXXXXX_add_project_to_ralph_tables.rb`
- `app/models/user.rb`
- `app/models/project.rb`
- `app/models/project_membership.rb`
- `app/models/current.rb`

**Files to modify:**
- `Gemfile`
- `app/models/webhook_event.rb`
- `app/models/ralph/base.rb`

### Phase 2: Authentication

**Tasks:**
1. Configure OmniAuth with GitHub provider
2. Configure Lockbox for encryption
3. Create SessionsController
4. Create Authentication concern
5. Update ApplicationController
6. Create login view
7. Add GitHub OAuth app registration docs

**Files to create:**
- `config/initializers/omniauth.rb`
- `config/initializers/lockbox.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/concerns/authentication.rb`
- `app/views/sessions/new.html.erb`

**Files to modify:**
- `app/controllers/application_controller.rb`
- `config/routes.rb`

### Phase 3: Authorization & Project Scoping

**Tasks:**
1. Create Authorization concern
2. Create ProjectScoping concern
3. Update ApplicationController with concerns
4. Create helper methods for authorization checks

**Files to create:**
- `app/controllers/concerns/authorization.rb`
- `app/controllers/concerns/project_scoping.rb`
- `app/helpers/authorization_helper.rb`

**Files to modify:**
- `app/controllers/application_controller.rb`

### Phase 4: Project Management UI

**Tasks:**
1. Create ProjectsController
2. Create ProjectMembersController
3. Create views for project management
4. Add project selector to navbar
5. Style new views

**Files to create:**
- `app/controllers/projects_controller.rb`
- `app/controllers/project_members_controller.rb`
- `app/views/projects/index.html.erb`
- `app/views/projects/new.html.erb`
- `app/views/projects/edit.html.erb`
- `app/views/projects/show.html.erb`
- `app/views/projects/_form.html.erb`
- `app/views/project_members/_list.html.erb`
- `app/views/project_members/_invite_form.html.erb`

**Files to modify:**
- `app/views/layouts/application.html.erb`
- `config/routes.rb`
- `app/assets/stylesheets/application.css`

### Phase 5: Ralph Integration Updates

**Tasks:**
1. Update Ralph controllers to be project-scoped
2. Update Ralph views with project context
3. Remove hardcoded Ralph configuration
4. Test Ralph queries with Current.project

**Files to modify:**
- `app/controllers/ralph/home_controller.rb`
- `app/controllers/ralph/issue_assignments_controller.rb`
- `app/controllers/ralph/models_controller.rb`
- `app/views/ralph/**/*.html.erb`
- `config/initializers/ralph.rb`
- `config/routes.rb`

### Phase 6: Webhook Updates

**Tasks:**
1. Update webhook routes to be project-scoped
2. Update GithubController to load project and verify project-specific secret
3. Update GithubWebhookSignatureService to accept secret parameter
4. Update all webhook jobs to include project_id
5. Update webhook event processor to be project-aware
6. Update webhook task creator to be project-scoped

**Files to modify:**
- `config/routes.rb`
- `app/controllers/webhooks/github_controller.rb`
- `app/services/github_webhook_signature_service.rb`
- `app/jobs/github_webhook_processor_job.rb`
- `app/services/github_webhook_event_processor.rb`
- `app/services/github_webhook_task_creator.rb`

### Phase 7: Job Updates

**Tasks:**
1. Update RalphTaskProcessorJob to accept and use project_id
2. Update job to set Current.project
3. Update job to configure Ralph per-project
4. Test job execution with multiple projects

**Files to modify:**
- `app/jobs/ralph_task_processor_job.rb`

### Phase 8: Testing

**Tasks:**
1. Create test fixtures for User, Project, ProjectMembership
2. Write authentication tests
3. Write authorization tests
4. Write project CRUD tests
5. Write project-scoped webhook tests
6. Write project-scoped job tests
7. Integration tests for multi-project workflow
8. Test project isolation (can't access other project's data)

**Files to create:**
- `test/fixtures/users.yml`
- `test/fixtures/projects.yml`
- `test/fixtures/project_memberships.yml`
- `test/controllers/sessions_controller_test.rb`
- `test/controllers/projects_controller_test.rb`
- `test/controllers/project_members_controller_test.rb`
- `test/models/user_test.rb`
- `test/models/project_test.rb`
- `test/models/project_membership_test.rb`
- `test/integration/multi_project_workflow_test.rb`
- `test/integration/project_isolation_test.rb`

**Files to modify:**
- `test/controllers/webhooks/github_controller_test.rb`
- `test/jobs/ralph_task_processor_job_test.rb`

### Phase 9: Documentation

**Tasks:**
1. Update README with multi-project setup
2. Create AUTHENTICATION.md guide
3. Create PROJECT_SETUP.md guide
4. Update WEBHOOK_ARCHITECTURE.md with project scoping
5. Add troubleshooting guide for multi-project issues

**Files to create:**
- `docs/AUTHENTICATION.md`
- `docs/PROJECT_SETUP.md`

**Files to modify:**
- `README.md`
- `WEBHOOK_ARCHITECTURE.md`
- `CLAUDE.md`

### Phase 10: Deployment & Seed Data

**Tasks:**
1. Create seed data for development
2. Update environment variable documentation
3. Update Kamal deployment config (if applicable)
4. Test deployment with multiple projects

**Seed Data (Development Only):**

```ruby
# db/seeds.rb
# Development seed data for testing multi-project setup

if Rails.env.development?
  puts "🌱 Seeding development data..."

  # Create test user
  user = User.find_or_create_by!(github_id: 123456) do |u|
    u.github_login = "testuser"
    u.github_name = "Test User"
    u.github_email = "test@example.com"
    u.github_avatar_url = "https://avatars.githubusercontent.com/u/123456"
  end
  puts "✓ Created user: #{user.github_login}"

  # Create test project
  project = Project.find_or_create_by!(slug: 'test-project') do |p|
    p.name = "Test Project"
    p.github_repository = "owner/test-repo"
    p.github_token = ENV.fetch('GITHUB_TOKEN', 'dummy_token_for_development')
    p.github_webhook_secret = SecureRandom.hex(32)
    p.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', 'dummy_api_key_for_development')
  end
  puts "✓ Created project: #{project.name}"

  # Make user the owner
  ProjectMembership.find_or_create_by!(user: user, project: project) do |m|
    m.role = 'owner'
  end
  puts "✓ Created project membership"

  puts "\n✅ Seed complete!"
  puts "   Login URL: http://localhost:3000/login"
  puts "   Test User: #{user.github_login}"
  puts "   Project: #{project.name} (#{project.slug})"
  puts "   Webhook URL: http://localhost:3000/webhooks/github/#{project.slug}"
end
```

**Files to create:**
- `db/seeds.rb`

**Files to modify:**
- `.env.example`

## Security Considerations

### Token Storage

**Use Lockbox for encrypting sensitive data:**
```ruby
# Gemfile
gem 'lockbox'
gem 'blind_index'  # Optional, for searchable encryption

# config/initializers/lockbox.rb
Lockbox.master_key = ENV["LOCKBOX_MASTER_KEY"]

# app/models/project.rb
class Project < ApplicationRecord
  encrypts :github_token
  encrypts :github_webhook_secret
  encrypts :anthropic_api_key
end
```

### Project Scoping Safety

**Multiple layers of protection:**

1. **Default Scope**: All Ralph models automatically scoped to `Current.project`
2. **Belongs To Association**: All Ralph models `belongs_to :project` with validation
3. **Controller Authorization**: Every action checks project access
4. **Guard Clauses**: Ralph::Base checks `Current.project` is set

```ruby
# app/models/ralph/base.rb
module Ralph
  class Base < ActiveRecord::Base
    belongs_to :project

    # Automatically scope all queries
    default_scope { where(project_id: Current.project&.id) if Current.project }

    # Validate project is set before creating
    validates :project, presence: true
  end
end
```

### Authorization Checks

**Every project-scoped action must verify:**
1. User is authenticated (`require_authentication`)
2. User has membership in project (`authorize_project_access!`)
3. User's role permits the action (`:viewer`, `:member`, or `:owner`)

### Webhook Signature Verification

**Each project has unique webhook secret:**
- Stored encrypted in database
- Verified per-project during webhook processing
- Prevents cross-project webhook replay attacks

## Data Isolation

### Single Database with Project Scoping

**Benefits:**
- Simpler connection management
- Standard Rails associations
- Easier cross-project queries (for admin features)
- Single backup/restore
- Better test isolation

**Safety Measures:**
1. **Automatic Scoping**: `default_scope` on Ralph::Base
2. **Validation**: `belongs_to :project, required: true`
3. **Controller Guards**: Authorization checks on every action
4. **Test Coverage**: Isolation tests ensure no cross-project leaks

### Job Isolation

**Each job execution is project-scoped:**
1. Load project from database
2. Set `Current.project` (enables automatic scoping)
3. Configure Ralph with project's credentials
4. Execute work (all Ralph queries scoped automatically)
5. Clear `Current.project` in ensure block

## Performance Considerations

### Query Optimization

**N+1 query prevention:**
```ruby
# Bad
@projects = current_user.projects
@projects.each { |p| p.issue_assignments.count }

# Good
@projects = current_user.projects
  .left_joins(:issue_assignments)
  .select('projects.*, COUNT(ralph_issue_assignments.id) as issue_count')
  .group('projects.id')
```

### Caching

**Project counts caching:**
```ruby
# app/models/project.rb
def issue_assignments_count
  Rails.cache.fetch("#{cache_key_with_version}/issue_assignments_count", expires_in: 5.minutes) do
    issue_assignments.count
  end
end
```

### Index Strategy

**Important indexes:**
- `project_id` on all Ralph tables (for scoping)
- `[project_id, github_issue_number]` unique index on ralph_issue_assignments
- `[project_id, github_pr_number]` unique index on ralph_pull_requests
- `[project_id, delivery_id]` unique index on webhook_events

## Testing Strategy

### Project Isolation Tests

**Critical test: Verify project data isolation**
```ruby
# test/integration/project_isolation_test.rb
class ProjectIsolationTest < ActionDispatch::IntegrationTest
  test "cannot access another project's data" do
    project1 = projects(:project_one)
    project2 = projects(:project_two)
    user = users(:alice)

    # User is member of project1 only
    project1.project_memberships.create!(user: user, role: 'member')

    sign_in user
    Current.project = project1

    # Should see project1 data
    assert_equal 2, Ralph::IssueAssignment.count

    # Switch to project2 (shouldn't be allowed, but test data isolation)
    Current.project = project2

    # Should see no data (not a member)
    assert_equal 0, Ralph::IssueAssignment.count
  end
end
```

## Environment Variables

**Required for multi-project setup:**
```bash
# Application
APP_HOST=ralph-on-rails.example.com  # Your app's public URL

# GitHub OAuth (for user authentication)
GITHUB_OAUTH_CLIENT_ID=Iv1.abc123...
GITHUB_OAUTH_CLIENT_SECRET=abc123def456...

# Encryption (for storing project secrets in database)
LOCKBOX_MASTER_KEY=abc123def456...  # Generate with: Lockbox.generate_key
```

**Notes:**
- No per-project environment variables needed! Project credentials stored encrypted in database
- Users create projects via web UI and enter their own tokens
- Generate lockbox key with: `bundle exec rails runner 'puts Lockbox.generate_key'`

## Deployment Checklist

- [ ] Add gems: `omniauth-github`, `omniauth-rails_csrf_protection`, `lockbox`
- [ ] Generate lockbox master key: `bundle exec rails runner 'puts Lockbox.generate_key'`
- [ ] Create GitHub OAuth app at https://github.com/settings/developers
- [ ] Set OAuth callback URL: `https://your-app.com/auth/github/callback`
- [ ] Add environment variables (APP_HOST, GITHUB_OAUTH_*, LOCKBOX_MASTER_KEY)
- [ ] Reset database: `bin/rails db:reset` (wipe old data, fresh schema)
- [ ] Run migrations: `bin/rails db:migrate`
- [ ] Test authentication flow
- [ ] Create first project via UI
- [ ] Configure GitHub webhook on repository
- [ ] Test webhook processing
- [ ] Test project isolation (create second project)
- [ ] Update documentation
- [ ] Deploy to production

## Summary

**Architecture: Single Database with Project Scoping**

This approach provides:
- ✅ Simple connection management (no dynamic switching)
- ✅ Standard Rails conventions (associations, scoping)
- ✅ Automatic query scoping via `default_scope`
- ✅ Complete data isolation via project_id
- ✅ Easy testing and debugging
- ✅ Better Rails integration

**Key Implementation Details:**
- Add `project_id` to all Ralph tables
- Use `default_scope` on Ralph::Base for automatic scoping
- Set `Current.project` in controllers and jobs
- Encrypt sensitive project data with Lockbox
- GitHub OAuth for authentication
- Role-based authorization (owner/member/viewer)
- Project-scoped webhook URLs

**Effort Estimate:**
- ~10 phases
- ~50-60 files to create/modify
- ~2-3 weeks development time
- Comprehensive test coverage
- Full documentation

Ready to implement! 🚀

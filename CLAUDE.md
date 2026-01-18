# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ralph-on-rails is a Rails 8.1 multi-tenant web application for managing and monitoring Ralph autonomous software engineer projects across multiple GitHub repositories.

**Key Architecture**: Multi-project design with single database:
- **Single Database**: All projects share one database with automatic scoping via `project_id`
- **GitHub OAuth**: User authentication via GitHub
- **Project Isolation**: All Ralph data is automatically scoped to the current project via `Current.project`
- **Per-Project Credentials**: Each project has encrypted GitHub token, webhook secret, and Anthropic API key
- **Project-Specific Webhooks**: Each project has a unique webhook URL for GitHub events

## Development Commands

### Setup
```bash
bin/setup              # Install dependencies, prepare database, start server
bin/setup --skip-server  # Install dependencies without starting server
bin/setup --reset      # Full reset with database recreation
```

### Running the Application
```bash
bin/dev                # Start development server
bin/rails server       # Start Rails server directly
```

### Testing
```bash
bin/rails test         # Run all tests
bin/rails test test/path/to/test.rb  # Run single test file
bin/rails test test/path/to/test.rb:LINE  # Run single test at line number
```

### Linting and Security
```bash
bin/rubocop            # Run Ruby style linter (rubocop-rails-omakase)
bin/brakeman           # Run security scanner
bin/bundler-audit      # Check gems for security vulnerabilities
bin/importmap audit    # Check importmap for vulnerabilities
```

### CI
```bash
bin/ci                 # Run full CI pipeline locally (setup, lint, security, tests)
```

### Database
```bash
bin/rails db:prepare   # Prepare database (create if needed, run migrations)
bin/rails db:reset     # Drop, create, and migrate database
bin/rails db:seed      # Load seed data
```

## Architecture

### Multi-Project Design

**Projects** (`app/models/project.rb`):
- Represent one GitHub repository each
- Store encrypted credentials (GitHub token, webhook secret, API key)
- Auto-generate URL slug and webhook secret
- Have many users through project_memberships

**Project Memberships** (`app/models/project_membership.rb`):
- Join table between users and projects
- Three roles: owner (full access), member (can trigger), viewer (read-only)
- Role hierarchy enforced via `Authorization` concern

**Users** (`app/models/user.rb`):
- Authenticated via GitHub OAuth
- Store GitHub user info and encrypted access token
- Have access to multiple projects with different roles

### Current Attributes (`app/models/current.rb`)

Request-scoped attributes for context:
```ruby
Current.user     # Authenticated user (set by Authentication concern)
Current.project  # Current project (set by ProjectScoping concern)
```

Setting `Current.project` automatically:
- Configures Ralph with project's credentials
- Scopes all Ralph queries to that project

### Ralph Models and Automatic Scoping

All Ralph models inherit from `Ralph::Base` (app/models/ralph/base.rb) which:
- Belongs to `:project`
- Has `default_scope { where(project_id: Current.project&.id) if Current.project }`
- Sets `table_name_prefix = "ralph_"` for all Ralph tables
- Makes all records readonly via `readonly?` method

**Automatic Query Scoping**:
```ruby
# In a controller with ProjectScoping concern
Current.project = Project.find_by(slug: params[:project_id])

# All Ralph queries are now automatically scoped
Ralph::IssueAssignment.all  # Only returns issues for Current.project
Ralph::PullRequest.all      # Only returns PRs for Current.project
```

**Available Ralph Models**:
- `Ralph::IssueAssignment` - Issues being worked on, with parent/child relationships
- `Ralph::PullRequest` - PRs associated with issue assignments
- `Ralph::DesignDocument` - Design docs for issues
- `Ralph::DesignDocComment` - Comments on design docs
- `Ralph::ClaudeSession` - Claude API sessions
- `Ralph::Iteration` - Development iterations
- `Ralph::TaskQueueItem` - Task queue items
- `Ralph::MainBranchHealth` - Health metrics for main branch

### Project-Scoped Routes

Routes are scoped by project slug:

```
/:project_id/ralph/                              # Project dashboard
/:project_id/ralph/issue_assignments             # Issues for project
/:project_id/ralph/issue_assignments/:id         # Issue details
/:project_id/ralph/models                        # Model browser
/:project_id/project                             # Project settings (owner only)
/:project_id/project/edit                        # Edit project (owner only)
```

**Webhook routes** (project-specific):
```
/webhooks/github/:project_id                     # GitHub webhook endpoint
```

### Controller Concerns

**Authentication** (`app/controllers/concerns/authentication.rb`):
- Sets `Current.user` from session
- `require_authentication` - Redirects to login if not authenticated
- Skip with `skip_before_action :require_authentication`

**Authorization** (`app/controllers/concerns/authorization.rb`):
- `authorize_project_access!(role)` - Check user has required role
- `can_access_project?(project, role)` - Check role hierarchy
- Raises `Authorization::NotAuthorizedError` if unauthorized

**ProjectScoping** (`app/controllers/concerns/project_scoping.rb`):
- Sets `Current.project` from `:project_id` URL parameter
- Calls `authorize_project_access!` automatically
- Skip with `skip_before_action :set_current_project`

### Configuration

**Environment Variables**:
```bash
# GitHub OAuth (for user authentication)
GITHUB_OAUTH_CLIENT_ID=...
GITHUB_OAUTH_CLIENT_SECRET=...

# Encryption keys (for credentials)
LOCKBOX_MASTER_KEY=...
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

**Per-Project Credentials** (stored encrypted in database):
- GitHub token - For repository API access
- Webhook secret - For verifying GitHub webhooks
- Anthropic API key - For Claude API access

Ralph is configured per-project automatically when `Current.project` is set:
```ruby
Current.project = project  # Triggers project.configure_ralph!
# Now Ralph.configuration uses this project's credentials
```

### Technology Stack

- **Rails 8.1** with Ruby 3.4.5
- **Hotwire**: Turbo + Stimulus for interactive UI
- **SQLite3**: Both primary and Ralph databases
- **Solid Cache/Queue/Cable**: Database-backed Rails subsystems
- **Importmap**: JavaScript module loading
- **Redcarpet**: Markdown rendering
- **Kamal**: Docker deployment

### Testing

Tests use:
- Minitest (Rails default)
- Parallel test execution enabled (`parallelize(workers: :number_of_processors)`)
- System tests with Capybara and Selenium WebDriver
- Fixtures from `test/fixtures/`

## Important Patterns

### Automatic Project Scoping

All Ralph queries are automatically scoped to `Current.project`:

```ruby
# This is handled automatically by ProjectScoping concern
Current.project = Project.find_by(slug: params[:project_id])

# All Ralph queries now return only this project's data
@issues = Ralph::IssueAssignment.all
# SQL: SELECT * FROM ralph_issue_assignments WHERE project_id = ?

# To query without scoping (rare):
Ralph::IssueAssignment.unscoped_by_project do
  Ralph::IssueAssignment.unscoped.all  # Returns all projects' data
end
```

### Read-Only Ralph Data

All Ralph models are marked readonly. Never attempt to create, update, or delete Ralph records through the web interface. Ralph data is created by:
- `RalphTaskProcessorJob` - Processes webhook events and creates Ralph records
- Ralph gem's Orchestrator - Creates issues, PRs, iterations during work

**When creating Ralph records in jobs:**
```ruby
# Always set the project explicitly
Current.project = @project

Ralph::IssueAssignment.create!(
  project: Current.project,  # Explicit assignment
  github_issue_number: 42,
  title: "Fix bug",
  # ... other attributes
)
```

### Role-Based Access Control

Always check user permissions before showing/hiding UI elements:

```ruby
# In views
<% if can_access_project?(@project, :owner) %>
  <%= link_to "Edit Project", edit_project_path(@project) %>
<% end %>

# In controllers
def update
  authorize_project_access!(:owner)  # Raises error if not owner
  @project.update!(project_params)
end
```

### Project Isolation

Each project is completely isolated:
- Separate Ralph data (issues, PRs, iterations)
- Separate webhooks and webhook events
- Separate credentials
- Separate team members

**Never** query across projects unless explicitly needed:
```ruby
# Good: Scoped to current project
@issues = Ralph::IssueAssignment.all

# Bad: Would see all projects (won't work anyway due to default_scope)
# @all_issues = Ralph::IssueAssignment.unscoped.all
```

### Encrypted Credentials

Project credentials are encrypted at rest:

```ruby
# Never log or display these
project.github_token          # Decrypted on access
project.anthropic_api_key     # Decrypted on access
project.github_webhook_secret # Decrypted on access

# Database stores ciphertext
project.github_token_ciphertext  # Encrypted blob
```

### Webhook Deduplication

Webhooks are deduplicated per-project using `[project_id, delivery_id]` unique index:

```ruby
# In GithubWebhookTaskCreator
webhook_event = project.webhook_events.find_by(delivery_id: delivery_id)
return if webhook_event  # Already processed

# Create new event
project.webhook_events.create!(
  delivery_id: delivery_id,
  # ... other attributes
)
```

### Issue Assignment Hierarchy

Issue assignments can have parent/child relationships:
- Use `parent_issue?` / `root_issue?` to check hierarchy
- Child issues have a `merge_order` for sequencing
- Access children via `child_issues` association (ordered by merge_order)

### Design Document Workflow

Design documents have states (`draft` / `published`) and approval tracking:
- Check approval with `approved?` method
- Get latest design doc for issue: `DesignDocument.latest_for_issue(issue_id)`
- Use scopes: `published`, `drafts`, `approved`

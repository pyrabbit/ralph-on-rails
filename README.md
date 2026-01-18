# Ralph on Rails

A multi-tenant Rails web application for managing and monitoring Ralph autonomous software engineer projects across multiple GitHub repositories.

## Overview

Ralph on Rails provides a centralized web interface for:
- Managing multiple Ralph projects (one per GitHub repository)
- Viewing issue assignments, pull requests, and design documents
- Monitoring Ralph's autonomous work across all your repositories
- Project-specific webhook handling and job processing
- Role-based access control (owner, member, viewer)

## Architecture

### Multi-Project Design

- **Single Database**: All projects share one database with automatic scoping via `project_id`
- **GitHub OAuth**: User authentication via GitHub
- **Project Isolation**: All Ralph data is automatically scoped to the current project
- **Per-Project Credentials**: Each project has its own encrypted GitHub token, webhook secret, and Anthropic API key
- **Project-Specific Webhooks**: Each project has a unique webhook URL for GitHub events

### Key Components

- **Projects**: Repository configurations with encrypted credentials
- **Project Memberships**: User-project relationships with roles (owner/member/viewer)
- **Ralph Models**: Issue assignments, PRs, design docs, iterations (all project-scoped)
- **Webhook Events**: Deduplication and processing tracking per project
- **Background Jobs**: Solid Queue processes tasks with automatic project context

## Requirements

- Ruby 3.4.5+
- Rails 8.1+
- SQLite3 (development) / PostgreSQL (production recommended)
- GitHub account and OAuth app
- Anthropic API key

## Installation

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd ralph-on-rails
bin/setup
```

### 2. Configure Environment Variables

Create a `.env` file:

```bash
# GitHub OAuth (create at https://github.com/settings/developers)
GITHUB_OAUTH_CLIENT_ID=your_oauth_client_id
GITHUB_OAUTH_CLIENT_SECRET=your_oauth_client_secret

# Encryption keys (generate with `rails secret`)
LOCKBOX_MASTER_KEY=generate_with_rails_secret
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=generate_with_rails_secret
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=generate_with_rails_secret
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=generate_with_rails_secret

# Optional: Rails secret key base
SECRET_KEY_BASE=generate_with_rails_secret
```

### 3. Setup Database

```bash
bin/rails db:create
bin/rails db:migrate
```

### 4. Start the Server

```bash
bin/dev
```

Visit http://localhost:3000 and sign in with GitHub.

## Usage

### Creating a Project

1. Sign in with GitHub OAuth
2. Navigate to Projects → New Project
3. Fill in:
   - **Name**: Human-readable project name
   - **GitHub Repository**: Format `owner/repo`
   - **GitHub Token**: Personal access token with repo permissions
   - **Anthropic API Key**: Claude API key for Ralph

The system will:
- Auto-generate a URL slug (e.g., `my-project` → `/my-project/`)
- Generate a unique webhook secret
- Set you as the project owner

### Setting Up GitHub Webhooks

After creating a project, configure GitHub webhooks:

1. Go to your repository → Settings → Webhooks → Add webhook
2. **Payload URL**: `https://your-domain.com/webhooks/github/PROJECT_SLUG`
3. **Content type**: `application/json`
4. **Secret**: Copy from project settings page
5. **Events**: Select:
   - Pull requests
   - Check runs
   - Issues
   - Pull request review comments
6. **Active**: ✓

### Project Roles

- **Owner**: Full access (edit, delete project, manage members)
- **Member**: Can trigger actions, view all data
- **Viewer**: Read-only access

## Development

### Running Tests

```bash
# All tests
bin/rails test

# Specific test file
bin/rails test test/models/project_test.rb

# With coverage
COVERAGE=true bin/rails test
```

### Code Quality

```bash
# Linter
bin/rubocop

# Security scan
bin/brakeman

# Dependency vulnerabilities
bin/bundle-audit
```

### Database Console

```bash
# Rails console with database access
bin/rails console

# Direct database access
bin/rails dbconsole
```

## Project Structure

```
app/
├── controllers/
│   ├── concerns/
│   │   ├── authentication.rb      # GitHub OAuth authentication
│   │   ├── authorization.rb       # Role-based access control
│   │   └── project_scoping.rb     # Automatic project context
│   ├── projects_controller.rb     # Project CRUD
│   ├── sessions_controller.rb     # Login/logout
│   └── webhooks/
│       └── github_controller.rb   # GitHub webhook handler
├── models/
│   ├── current.rb                 # Request-scoped user/project context
│   ├── project.rb                 # Project configuration
│   ├── project_membership.rb     # User-project roles
│   ├── user.rb                    # GitHub users
│   ├── webhook_event.rb          # Webhook deduplication
│   └── ralph/                     # Ralph models (auto-scoped)
│       ├── base.rb               # Base class with default_scope
│       ├── issue_assignment.rb
│       ├── pull_request.rb
│       └── ...
├── jobs/
│   ├── github_webhook_processor_job.rb   # Parse webhook events
│   └── ralph_task_processor_job.rb       # Execute Ralph work
└── services/
    ├── github_webhook_event_processor.rb  # Event routing
    ├── github_webhook_task_creator.rb     # Job creation
    └── github_webhook_signature_service.rb # Security

config/
├── initializers/
│   ├── lockbox.rb                # Encryption config
│   └── omniauth.rb              # GitHub OAuth config
└── routes.rb                     # Project-scoped routes

lib/ralph/                        # Ralph gem integration
```

## Key Features

### Automatic Project Scoping

All Ralph queries are automatically scoped to the current project:

```ruby
# In a controller with ProjectScoping concern
def show
  # Current.project is automatically set from URL /:project_id/
  @issues = Ralph::IssueAssignment.all  # Only returns current project's issues
end
```

### Encrypted Credentials

Project credentials are encrypted at rest using ActiveRecord::Encryption:

```ruby
project = Project.create!(
  name: "My Project",
  github_token: "ghp_secret",        # Encrypted in DB
  anthropic_api_key: "sk-ant-key"   # Encrypted in DB
)

# Access decrypted values
project.github_token  # => "ghp_secret"
```

### Project-Specific Configuration

Ralph is configured per-project automatically:

```ruby
Current.project = project
# Ralph.configuration now uses project's tokens and repository
```

### Webhook Deduplication

Prevents duplicate processing of the same webhook:

```ruby
# WebhookEvent has unique index on [project_id, delivery_id]
webhook_event = project.webhook_events.find_by(delivery_id: delivery_id)
return if webhook_event  # Already processed
```

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment instructions.

### Quick Deploy with Kamal

```bash
# Setup .env.production
kamal setup

# Deploy
kamal deploy
```

## Documentation

- [AUTHENTICATION.md](AUTHENTICATION.md) - GitHub OAuth setup and flow
- [PROJECT_SETUP.md](PROJECT_SETUP.md) - Creating and configuring projects
- [CLAUDE.md](CLAUDE.md) - Instructions for Claude Code (AI pair programmer)
- [MULTI_PROJECT_PLAN.md](MULTI_PROJECT_PLAN.md) - Multi-tenant architecture design

## Troubleshooting

### "Ralph configuration not found"

This warning is normal. Ralph is configured per-project at runtime, not via a static config file.

### Webhook signature validation fails

Verify:
1. Webhook secret matches between GitHub and project settings
2. Payload URL includes correct project slug
3. Content-Type is `application/json`

### Background jobs not processing

Check Solid Queue is running:

```bash
bin/rails solid_queue:start
```

### Project isolation not working

Ensure `Current.project` is set:

```ruby
# In controllers using ProjectScoping concern
Current.project  # Should return the current project
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run `bin/ci` to verify all checks pass
5. Submit a pull request

## License

[Add your license here]

## Support

For issues and questions, please use the GitHub issue tracker.

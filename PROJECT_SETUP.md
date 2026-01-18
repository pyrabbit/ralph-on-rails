# Project Setup Guide

Complete guide for creating, configuring, and managing Ralph projects.

## Table of Contents

- [Overview](#overview)
- [Creating a Project](#creating-a-project)
- [GitHub Token Setup](#github-token-setup)
- [Anthropic API Key](#anthropic-api-key)
- [Webhook Configuration](#webhook-configuration)
- [Project Settings](#project-settings)
- [Managing Team Members](#managing-team-members)
- [Multiple Projects](#multiple-projects)
- [Troubleshooting](#troubleshooting)

## Overview

Each Ralph project represents:
- One GitHub repository
- Isolated Ralph data (issues, PRs, iterations)
- Separate credentials (GitHub token, API keys)
- Unique webhook endpoint
- Team members with specific roles

## Creating a Project

### Prerequisites

1. **GitHub Repository**: You need a GitHub repository where Ralph will work
2. **GitHub Personal Access Token**: For Ralph to interact with the repository
3. **Anthropic API Key**: For Ralph to use Claude
4. **Repository Access**: You must have admin access to the repository

### Step-by-Step Guide

#### 1. Sign In

Navigate to your Ralph on Rails instance and sign in with GitHub.

#### 2. Create New Project

1. Click **"Projects"** in the navigation
2. Click **"New Project"** button
3. Fill out the form:

**Project Name**
- Human-readable name (e.g., "ACME Web App")
- Used in the UI and notifications
- Can contain spaces and special characters

**GitHub Repository**
- Format: `owner/repository`
- Example: `acme-corp/web-app`
- Must match exactly (case-sensitive)

**GitHub Token**
- Personal access token with repo permissions
- See [GitHub Token Setup](#github-token-setup) below
- Encrypted at rest in the database

**Anthropic API Key**
- Claude API key from Anthropic
- See [Anthropic API Key](#anthropic-api-key) below
- Encrypted at rest in the database

#### 3. Auto-Generated Fields

The system automatically generates:

**Slug**
- URL-friendly identifier (e.g., `acme-web-app`)
- Generated from project name
- Used in URLs: `/acme-web-app/`
- Can be customized before creating

**Webhook Secret**
- Secure random string
- Used to verify GitHub webhook signatures
- Generated after project creation
- Copy this for GitHub webhook configuration

#### 4. Confirm Creation

Click **"Create Project"**. You'll be:
- Set as the project owner
- Redirected to the project dashboard
- Shown the webhook configuration instructions

## GitHub Token Setup

### Required Permissions

Your GitHub personal access token needs these scopes:

**Classic Token (recommended for now):**
- `repo` - Full control of private repositories
  - `repo:status` - Access commit status
  - `repo_deployment` - Access deployment status
  - `public_repo` - Access public repositories
  - `repo:invite` - Access repository invitations
- `read:org` - Read organization membership (optional)

**Fine-Grained Token (future):**
- Repository permissions:
  - Contents: Read and write
  - Issues: Read and write
  - Pull requests: Read and write
  - Metadata: Read-only

### Creating a Token

#### Option 1: Classic Token (Easier)

1. Go to https://github.com/settings/tokens
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Name: `Ralph on Rails - [Repository Name]`
4. Expiration: Choose based on your security policy
5. Select scopes:
   - ☑️ `repo` (all sub-scopes)
6. Click **"Generate token"**
7. **Copy the token immediately** (you won't see it again)
8. Paste into Ralph project creation form

#### Option 2: Fine-Grained Token (More Secure)

1. Go to https://github.com/settings/tokens?type=beta
2. Click **"Generate new token"**
3. Token name: `Ralph - [Repository Name]`
4. Expiration: Choose based on policy
5. Repository access: **"Only select repositories"**
6. Select your repository
7. Permissions:
   - Contents: Read and write
   - Issues: Read and write
   - Pull requests: Read and write
   - Metadata: Read-only
8. Click **"Generate token"**
9. Copy and paste into Ralph

### Token Security

**Best Practices:**
- One token per project (easier to revoke)
- Set expiration dates
- Use fine-grained tokens when possible
- Rotate tokens regularly
- Revoke immediately if compromised

**Token is encrypted:**
```ruby
# In database
github_token_ciphertext: "encrypted_blob..."

# In application
project.github_token  # => Decrypted value
```

## Anthropic API Key

### Getting an API Key

1. Go to https://console.anthropic.com/
2. Sign in or create an account
3. Navigate to **API Keys**
4. Click **"Create Key"**
5. Name: `Ralph - [Project Name]`
6. Copy the key (starts with `sk-ant-`)

### API Key Billing

- Anthropic charges per API call
- Monitor usage in Anthropic console
- Set spending limits to avoid surprises
- Different models have different costs

### API Key Security

- Encrypted in database
- Never logged or displayed
- One key per project recommended
- Rotate if compromised

## Webhook Configuration

After creating a project, configure GitHub to send webhooks to Ralph.

### 1. Get Webhook URL

From your project dashboard, copy:
- **Webhook URL**: `https://your-domain.com/webhooks/github/PROJECT_SLUG`
- **Webhook Secret**: Shown in project settings

### 2. Configure in GitHub

1. Go to your repository on GitHub
2. Click **Settings** → **Webhooks** → **Add webhook**

3. **Payload URL**:
   ```
   https://your-domain.com/webhooks/github/PROJECT_SLUG
   ```

4. **Content type**: `application/json`

5. **Secret**: Paste the webhook secret from Ralph

6. **Which events?**: Select individual events:
   - ☑️ Pull requests
   - ☑️ Check runs
   - ☑️ Issues
   - ☑️ Pull request review comments

7. **Active**: ☑️ Checked

8. Click **Add webhook**

### 3. Verify Configuration

GitHub will send a test ping. Check:
1. Green checkmark next to webhook in GitHub
2. Recent Deliveries tab shows successful delivery (200 response)
3. In Ralph, check webhook events are being received

### Webhook Events Handled

| Event | Action | Triggers |
|-------|--------|----------|
| `pull_request` | `synchronize`, `opened` | PR maintenance if unmergeable |
| `check_run` | `completed` | PR maintenance if checks fail |
| `issues` | `labeled`, `opened` | New issue task if "help wanted" |
| `pull_request_review_comment` | `created` | PR review response task |

### Troubleshooting Webhooks

**Webhook shows red X:**
- Check webhook URL matches exactly
- Verify webhook secret matches
- Ensure app is accessible from internet

**No events received in Ralph:**
- Check webhook is active
- Verify event types are selected
- Check logs for signature validation errors

**Signature validation fails:**
- Webhook secret doesn't match
- GitHub may have cached old secret (wait 5min or recreate webhook)

## Project Settings

### Viewing Project Settings

Navigate to: `/YOUR_PROJECT_SLUG/project/edit`

### Editable Settings

**Project Name**
- Display name in UI
- Can be changed anytime

**GitHub Repository**
- **Cannot be changed** after creation
- Would break webhook configuration
- Create new project if repository changes

**GitHub Token**
- Update if token rotated
- Re-encrypted on save

**Webhook Secret**
- Update if compromised
- Must update in GitHub webhook configuration

**Anthropic API Key**
- Update if key rotated
- Re-encrypted on save

**Active Status**
- Deactivate to temporarily pause webhook processing
- Reactivate to resume

### Deleting a Project

**Warning**: Deletion is permanent and removes:
- All Ralph data (issues, PRs, iterations)
- All webhook events
- All project memberships

To delete:
1. Navigate to project settings
2. Scroll to bottom
3. Click **"Delete Project"**
4. Confirm deletion

**You must be the project owner to delete.**

## Managing Team Members

### Roles

**Owner** (one per project)
- Full access
- Can edit project settings
- Can delete project
- Can manage members
- Can view and trigger all Ralph operations

**Member**
- Can view all project data
- Can trigger Ralph operations
- Cannot edit project settings
- Cannot delete project
- Cannot manage members

**Viewer**
- Read-only access
- Can view project dashboard
- Can view issues and PRs
- Cannot trigger operations
- Cannot edit anything

### Adding Members

1. Navigate to project settings
2. Click **"Members"** tab
3. Click **"Add Member"**
4. Enter GitHub username
5. Select role
6. Click **"Add"**

User must have signed into Ralph at least once.

### Changing Roles

1. Project settings → Members
2. Find member in list
3. Change role dropdown
4. Click **"Update"**

### Removing Members

1. Project settings → Members
2. Find member in list
3. Click **"Remove"**
4. Confirm removal

### Transferring Ownership

1. Promote another member to owner (only one owner allowed)
2. System will automatically demote previous owner to member
3. Or: Remove all members, delete project, and recreate under new owner

## Multiple Projects

### Project Isolation

Each project is completely isolated:
- Separate Ralph data
- Separate webhooks
- Separate credentials
- Separate team members

### Switching Between Projects

From any page:
1. Click project name in top navigation
2. Select different project from dropdown
3. All data updates to show selected project

### URL Structure

Each project has its own URL space:
```
/PROJECT_SLUG/                           # Project dashboard
/PROJECT_SLUG/ralph/issue_assignments    # Issues for this project
/PROJECT_SLUG/ralph/pull_requests        # PRs for this project
```

### Dashboard View

`/projects` shows all projects you have access to:
- Projects where you're owner
- Projects where you're member
- Projects where you're viewer

## Troubleshooting

### "Cannot create project: Repository not found"

**Cause**: GitHub token doesn't have access to repository

**Solution**:
1. Verify repository name is correct
2. Ensure token has `repo` scope
3. Check repository exists and you have access
4. Try accessing repository via GitHub web to verify

### "Webhook secret validation failed"

**Cause**: Secret mismatch between Ralph and GitHub

**Solution**:
1. Copy secret from Ralph project settings
2. Update GitHub webhook configuration
3. GitHub may cache old secret (wait 5 minutes)
4. Or delete and recreate webhook

### "Ralph configuration not found"

**Cause**: This is normal - Ralph is configured per-project at runtime

**Solution**:
- No action needed
- Warning can be ignored
- Each request sets Ralph.configuration based on Current.project

### "Project slug already taken"

**Cause**: Another project already uses this slug

**Solution**:
1. Use different project name
2. Or manually set custom slug before creating

### "Encryption error when saving"

**Cause**: Encryption keys not configured

**Solution**:
1. Verify `.env` has all encryption keys
2. Generate with `rails secret` if missing
3. Restart Rails server

### "Cannot access project"

**Cause**: No project membership

**Solution**:
1. Ask project owner to add you as member
2. Or: Owner needs to create project membership
3. Check you're signed in with correct GitHub account

## Best Practices

### Token Management

- ✅ One token per project
- ✅ Set expiration dates
- ✅ Document token purpose
- ✅ Rotate regularly (every 90 days)
- ❌ Don't share tokens between projects
- ❌ Don't commit tokens to git

### Project Organization

- ✅ Use descriptive project names
- ✅ Keep repository name accurate
- ✅ Add team members proactively
- ✅ Document project purpose
- ❌ Don't create duplicate projects

### Security

- ✅ Use fine-grained tokens when possible
- ✅ Set appropriate expiration
- ✅ Use viewer role for read-only access
- ✅ Audit team members regularly
- ❌ Don't give everyone owner role
- ❌ Don't use one token for everything

### Webhooks

- ✅ Verify webhook delivery after setup
- ✅ Monitor webhook failures
- ✅ Keep webhook secret secure
- ✅ Update secret if compromised
- ❌ Don't expose webhook URL publicly
- ❌ Don't reuse secrets across projects

## API Reference

### Project Model

```ruby
project = Project.find_by(slug: 'my-project')

# Attributes
project.name                  # "My Project"
project.slug                  # "my-project"
project.github_repository     # "owner/repo"
project.github_token          # Decrypted token
project.github_webhook_secret # Decrypted secret
project.anthropic_api_key     # Decrypted key
project.active?               # true/false

# Associations
project.users                 # All users with access
project.project_memberships   # Membership records
project.webhook_events        # Webhook history
project.issue_assignments     # Ralph issues
project.pull_requests         # Ralph PRs

# Methods
project.owner                 # User who owns project
project.configure_ralph!      # Set Ralph.configuration
```

### ProjectMembership Model

```ruby
membership = ProjectMembership.find(...)

# Attributes
membership.role               # "owner", "member", or "viewer"

# Methods
membership.owner?             # Check if owner
membership.member?            # Check if member
membership.viewer?            # Check if viewer
membership.has_role_level?(:member)  # Check role hierarchy
```

## Additional Resources

- [README.md](README.md) - Full application documentation
- [AUTHENTICATION.md](AUTHENTICATION.md) - GitHub OAuth setup
- [WEBHOOK_IMPLEMENTATION.md](WEBHOOK_IMPLEMENTATION.md) - Webhook architecture details

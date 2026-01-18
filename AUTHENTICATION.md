# Authentication Guide

Ralph on Rails uses GitHub OAuth for user authentication. This guide covers setup and troubleshooting.

## Table of Contents

- [Overview](#overview)
- [GitHub OAuth App Setup](#github-oauth-app-setup)
- [Configuration](#configuration)
- [Authentication Flow](#authentication-flow)
- [Development Setup](#development-setup)
- [Production Setup](#production-setup)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Overview

### Why GitHub OAuth?

- **Single Sign-On**: Users authenticate with their existing GitHub accounts
- **No Password Management**: No need to store or manage user passwords
- **GitHub Integration**: Direct access to repository permissions and user data
- **Security**: Leverages GitHub's security infrastructure

### What Gets Stored

When a user signs in, we store:
- GitHub user ID (primary identifier)
- GitHub login (username)
- GitHub name and email
- GitHub avatar URL
- Encrypted GitHub access token (for API calls)

## GitHub OAuth App Setup

### 1. Create a GitHub OAuth App

**For Development:**

1. Go to https://github.com/settings/developers
2. Click "New OAuth App"
3. Fill in:
   - **Application name**: `Ralph on Rails (Development)`
   - **Homepage URL**: `http://localhost:3000`
   - **Authorization callback URL**: `http://localhost:3000/auth/github/callback`
4. Click "Register application"
5. Note the **Client ID**
6. Click "Generate a new client secret" and note the **Client Secret**

**For Production:**

1. Follow same steps but use production URLs:
   - **Homepage URL**: `https://your-domain.com`
   - **Authorization callback URL**: `https://your-domain.com/auth/github/callback`

### 2. Configure Scopes

The OAuth app requests these scopes:
- `user:email` - Read user email address
- `read:org` - Read organization membership (for future features)

Scopes are configured in `config/initializers/omniauth.rb`:

```ruby
provider :github,
  ENV['GITHUB_OAUTH_CLIENT_ID'],
  ENV['GITHUB_OAUTH_CLIENT_SECRET'],
  scope: 'user:email,read:org'
```

## Configuration

### Environment Variables

Add to your `.env` file:

```bash
# Development
GITHUB_OAUTH_CLIENT_ID=your_development_client_id
GITHUB_OAUTH_CLIENT_SECRET=your_development_client_secret

# Production (use different app)
GITHUB_OAUTH_CLIENT_ID=your_production_client_id
GITHUB_OAUTH_CLIENT_SECRET=your_production_client_secret
```

### Generate Encryption Keys

User access tokens are encrypted. Generate keys:

```bash
# Generate four keys
rails secret
# Copy each output to .env

# Add to .env:
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
LOCKBOX_MASTER_KEY=...
```

## Authentication Flow

### 1. User Clicks "Sign in with GitHub"

```ruby
# app/views/sessions/new.html.erb
<%= link_to "Sign in with GitHub", "/auth/github",
    method: :post, class: "btn btn-primary" %>
```

### 2. Redirect to GitHub

OmniAuth middleware intercepts `/auth/github` and redirects to GitHub's OAuth authorization page.

### 3. User Authorizes

User sees GitHub's authorization prompt and clicks "Authorize application".

### 4. GitHub Callback

GitHub redirects back to `/auth/github/callback` with authorization code.

### 5. OmniAuth Exchanges Code for Token

OmniAuth automatically:
- Exchanges authorization code for access token
- Fetches user profile from GitHub API
- Builds auth hash with user data

### 6. SessionsController#create

```ruby
def create
  auth = request.env['omniauth.auth']
  user = User.find_or_create_from_github(auth)
  session[:user_id] = user.id
  redirect_to projects_path, notice: "Signed in as #{user.github_login}"
end
```

### 7. Current User Context

The `Authentication` concern sets `Current.user` on each request:

```ruby
# app/controllers/concerns/authentication.rb
def set_current_user
  if session[:user_id]
    Current.user = User.find_by(id: session[:user_id])
  end
end
```

### 8. Authorization

All controller actions require authentication by default:

```ruby
# app/controllers/application_controller.rb
before_action :require_authentication

def require_authentication
  unless Current.user
    redirect_to login_path, alert: "Please sign in to continue"
  end
end
```

## Development Setup

### 1. Install ngrok (for testing with GitHub)

If you want to test OAuth from GitHub's perspective:

```bash
# Install ngrok
brew install ngrok

# Start ngrok
ngrok http 3000

# Update GitHub OAuth app callback URL to ngrok URL:
# https://abc123.ngrok.io/auth/github/callback
```

### 2. Start Rails Server

```bash
bin/dev
```

### 3. Test Authentication

1. Visit http://localhost:3000
2. Click "Sign in with GitHub"
3. Authorize the application
4. You should be redirected back and signed in

## Production Setup

### 1. Create Production OAuth App

Use production domain for callback URL:
```
https://your-domain.com/auth/github/callback
```

### 2. Set Production Environment Variables

```bash
# In your deployment platform (Heroku, Render, etc.)
GITHUB_OAUTH_CLIENT_ID=prod_client_id
GITHUB_OAUTH_CLIENT_SECRET=prod_client_secret
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
LOCKBOX_MASTER_KEY=...
```

### 3. HTTPS Required

GitHub OAuth requires HTTPS in production. Ensure your app is served over HTTPS.

## Testing

### Test Mode Configuration

Tests use OmniAuth test mode to mock GitHub responses:

```ruby
# test/test_helper.rb or individual tests
OmniAuth.config.test_mode = true
OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
  'provider' => 'github',
  'uid' => '12345',
  'info' => {
    'nickname' => 'testuser',
    'name' => 'Test User',
    'email' => 'test@example.com',
    'image' => 'https://example.com/avatar.png'
  },
  'credentials' => {
    'token' => 'mock_token'
  }
})

# Trigger callback
get '/auth/github/callback'
```

### Helper Methods

```ruby
# Sign in a user in tests
sign_in_as users(:alice)

# Check if authenticated
assert Current.user.present?

# Sign out
sign_out
assert_nil Current.user
```

## Troubleshooting

### "The redirect_uri MUST match the registered callback URL"

**Cause**: OAuth callback URL doesn't match what's registered in GitHub app

**Solution**:
1. Check your GitHub OAuth app settings
2. Ensure callback URL exactly matches (including http/https, port, path)
3. No trailing slashes

### "Authentication failed: csrf_detected"

**Cause**: CSRF token mismatch in OAuth flow

**Solution**:
1. Ensure you're using POST for `/auth/github` (not GET)
2. Check `omniauth-rails_csrf_protection` gem is installed
3. Clear browser cookies and try again

### "User created but session not set"

**Cause**: Session not persisting across redirects

**Solution**:
1. Check `config/initializers/session_store.rb` exists
2. Verify cookies are enabled in browser
3. In development, ensure you're not in incognito/private mode

### "Access token not encrypted"

**Cause**: Encryption keys not configured

**Solution**:
1. Verify all encryption keys are set in `.env`
2. Restart Rails server after adding keys
3. Check `config/environments/production.rb` or `test.rb` for encryption config

### "OmniAuth::Strategies::OAuth2::CallbackError"

**Cause**: GitHub API returned an error

**Solution**:
1. Check GitHub OAuth app is not suspended
2. Verify client ID and secret are correct
3. Check GitHub status page for outages

### Testing Authentication in Development

```ruby
# Rails console
rails c

# Create a test user manually
user = User.create!(
  github_id: 99999,
  github_login: 'testuser',
  github_name: 'Test User',
  github_email: 'test@example.com'
)

# In controller tests or browser console
session[:user_id] = user.id
```

## Security Considerations

### Access Token Storage

- Tokens are encrypted using ActiveRecord::Encryption
- Never log or display access tokens
- Rotate encryption keys if compromised

### Session Management

- Sessions are stored server-side (not in cookies)
- Session timeout: 2 weeks (configurable)
- Clear sessions on logout

### CSRF Protection

- All non-GET requests require CSRF token
- OmniAuth uses `omniauth-rails_csrf_protection` gem
- Webhooks skip CSRF (verified by signature)

### Secure Cookies

Production configuration:

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_ralph_session',
  secure: Rails.env.production?,  # HTTPS only
  httponly: true,                  # No JavaScript access
  same_site: :lax                  # CSRF protection
```

## API Reference

### User Model

```ruby
user = User.find_by(github_login: 'username')

# Attributes
user.github_id           # GitHub user ID (integer)
user.github_login        # Username
user.github_name         # Full name
user.github_email        # Email address
user.github_avatar_url   # Avatar image URL
user.github_access_token # Encrypted access token

# Associations
user.projects            # Projects user has access to
user.project_memberships # Membership records with roles
```

### SessionsController Actions

```ruby
# GET /login
sessions#new

# POST /auth/github
# (Handled by OmniAuth middleware)

# GET /auth/github/callback
sessions#create

# GET /auth/failure
sessions#failure

# DELETE /logout
sessions#destroy
```

### Authentication Concern Methods

```ruby
# In any controller including Authentication

Current.user              # Current authenticated user
authenticated?            # Check if user is signed in
require_authentication    # Redirect to login if not authenticated
```

## Additional Resources

- [OmniAuth GitHub Strategy](https://github.com/omniauth/omniauth-github)
- [GitHub OAuth Documentation](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Rails Encrypted Credentials](https://edgeguides.rubyonrails.org/security.html#custom-credentials)

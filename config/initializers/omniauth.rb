# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github,
    ENV['GITHUB_OAUTH_CLIENT_ID'],
    ENV['GITHUB_OAUTH_CLIENT_SECRET'],
    scope: 'user:email,read:org'
end

# Allow OmniAuth to work with Rails CSRF protection
OmniAuth.config.allowed_request_methods = [:get, :post]

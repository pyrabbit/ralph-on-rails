ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Setup encrypted credentials for project fixtures
    def setup_project_credentials(project,
                                   github_token: "ghp_test_token_#{project.slug}",
                                   webhook_secret: "test_webhook_secret_#{project.slug}",
                                   api_key: "test_api_key_#{project.slug}")
      project.update!(
        github_token: github_token,
        github_webhook_secret: webhook_secret,
        anthropic_api_key: api_key
      )
    end

    # Setup all fixture projects with test credentials
    def setup_all_project_credentials
      Project.find_each do |project|
        setup_project_credentials(project)
      end
    end

    # Sign in as a user in integration tests
    def sign_in_as(user)
      if respond_to?(:session)
        # For integration tests
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
          'provider' => 'github',
          'uid' => user.github_id.to_s,
          'info' => {
            'nickname' => user.github_login,
            'name' => user.github_name,
            'email' => user.github_email,
            'image' => user.github_avatar_url
          },
          'credentials' => {
            'token' => 'test_token'
          }
        })
        get '/auth/github/callback'
      else
        # For unit/controller tests - manually set Current
        Current.user = user
      end
    end

    # Sign out current user
    def sign_out
      if respond_to?(:session)
        delete logout_path
      else
        Current.user = nil
      end
    end

    # Set current project for testing
    def set_current_project(project)
      Current.project = project
    end

    # Clear current attributes after each test
    teardown do
      Current.user = nil
      Current.project = nil
    end
  end
end

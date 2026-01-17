# Configure Ralph with environment variables
Ralph.configure do |config|
  config.github_token = ENV["GITHUB_TOKEN"]
  config.claude_api_key = ENV["ANTHROPIC_API_KEY"]
  config.repository = ENV["GITHUB_REPOSITORY"]
end

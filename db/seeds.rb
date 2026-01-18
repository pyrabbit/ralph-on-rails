# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding database..."

# Only seed in development environment
unless Rails.env.development?
  puts "⚠️  Skipping seed data - only run in development environment"
  exit
end

# Ensure encryption keys are configured
unless ENV['LOCKBOX_MASTER_KEY'].present? && ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?
  puts "⚠️  Warning: Encryption keys not configured. Set LOCKBOX_MASTER_KEY and related keys in .env"
  puts "   Generate with: rails secret"
  exit
end

# Create demo users (these would normally sign in via GitHub OAuth)
puts "\n👥 Creating demo users..."

demo_user = User.find_or_create_by!(github_id: 99999999) do |user|
  user.github_login = 'demo-user'
  user.github_name = 'Demo User'
  user.github_email = 'demo@example.com'
  user.github_avatar_url = 'https://avatars.githubusercontent.com/u/99999999'
  user.github_access_token = 'demo_token_not_real'  # Encrypted
end
puts "  ✓ Created/found demo user: #{demo_user.github_login}"

alice = User.find_or_create_by!(github_id: 88888888) do |user|
  user.github_login = 'alice-developer'
  user.github_name = 'Alice Developer'
  user.github_email = 'alice@example.com'
  user.github_avatar_url = 'https://avatars.githubusercontent.com/u/88888888'
  user.github_access_token = 'alice_token_not_real'
end
puts "  ✓ Created/found user: #{alice.github_login}"

bob = User.find_or_create_by!(github_id: 77777777) do |user|
  user.github_login = 'bob-engineer'
  user.github_name = 'Bob Engineer'
  user.github_email = 'bob@example.com'
  user.github_avatar_url = 'https://avatars.githubusercontent.com/u/77777777'
  user.github_access_token = 'bob_token_not_real'
end
puts "  ✓ Created/found user: #{bob.github_login}"

# Create demo projects
puts "\n📦 Creating demo projects..."

demo_project = Project.find_or_create_by!(slug: 'demo-project') do |project|
  project.name = 'Demo Project'
  project.github_repository = 'demo-org/demo-repo'
  project.github_token = 'ghp_demo_token_not_real_1234567890'  # Encrypted
  project.anthropic_api_key = 'sk-ant-demo-key-not-real'  # Encrypted
  project.active = true
end
puts "  ✓ Created/found project: #{demo_project.name} (#{demo_project.slug})"
puts "    Webhook URL: /webhooks/github/#{demo_project.slug}"

acme_web = Project.find_or_create_by!(slug: 'acme-web-app') do |project|
  project.name = 'ACME Web Application'
  project.github_repository = 'acme-corp/web-app'
  project.github_token = 'ghp_acme_web_token_not_real'
  project.anthropic_api_key = 'sk-ant-acme-web-key'
  project.active = true
end
puts "  ✓ Created/found project: #{acme_web.name} (#{acme_web.slug})"

acme_api = Project.find_or_create_by!(slug: 'acme-api') do |project|
  project.name = 'ACME API'
  project.github_repository = 'acme-corp/api'
  project.github_token = 'ghp_acme_api_token_not_real'
  project.anthropic_api_key = 'sk-ant-acme-api-key'
  project.active = true
end
puts "  ✓ Created/found project: #{acme_api.name} (#{acme_api.slug})"

inactive_project = Project.find_or_create_by!(slug: 'archived-project') do |project|
  project.name = 'Archived Project'
  project.github_repository = 'acme-corp/old-project'
  project.github_token = 'ghp_archived_token'
  project.anthropic_api_key = 'sk-ant-archived-key'
  project.active = false
end
puts "  ✓ Created/found project: #{inactive_project.name} (#{inactive_project.slug}) [INACTIVE]"

# Create project memberships
puts "\n🔐 Creating project memberships..."

# Demo user is owner of demo project
ProjectMembership.find_or_create_by!(user: demo_user, project: demo_project) do |membership|
  membership.role = 'owner'
end
puts "  ✓ #{demo_user.github_login} -> #{demo_project.slug} (owner)"

# Alice is owner of acme-web, member of acme-api
ProjectMembership.find_or_create_by!(user: alice, project: acme_web) do |membership|
  membership.role = 'owner'
end
puts "  ✓ #{alice.github_login} -> #{acme_web.slug} (owner)"

ProjectMembership.find_or_create_by!(user: alice, project: acme_api) do |membership|
  membership.role = 'member'
end
puts "  ✓ #{alice.github_login} -> #{acme_api.slug} (member)"

# Bob is owner of acme-api, member of acme-web
ProjectMembership.find_or_create_by!(user: bob, project: acme_api) do |membership|
  membership.role = 'owner'
end
puts "  ✓ #{bob.github_login} -> #{acme_api.slug} (owner)"

ProjectMembership.find_or_create_by!(user: bob, project: acme_web) do |membership|
  membership.role = 'member'
end
puts "  ✓ #{bob.github_login} -> #{acme_web.slug} (member)"

# Demo user is viewer of acme-web
ProjectMembership.find_or_create_by!(user: demo_user, project: acme_web) do |membership|
  membership.role = 'viewer'
end
puts "  ✓ #{demo_user.github_login} -> #{acme_web.slug} (viewer)"

# Summary
puts "\n📊 Seed Summary:"
puts "  Users: #{User.count}"
puts "  Projects: #{Project.count} (#{Project.where(active: true).count} active)"
puts "  Memberships: #{ProjectMembership.count}"
puts ""
puts "🎉 Seed completed successfully!"
puts ""
puts "📝 Next steps:"
puts "  1. Sign in via GitHub OAuth at http://localhost:3000"
puts "  2. Or use Rails console to set session manually:"
puts "     rails c"
puts "     > session = ActionDispatch::Request::Session.new"
puts "     > session[:user_id] = User.find_by(github_login: 'demo-user').id"
puts ""
puts "🔗 Demo project webhook URL:"
puts "   http://localhost:3000/webhooks/github/demo-project"
puts ""
puts "⚠️  Remember: These are demo credentials. Replace with real tokens for actual use."

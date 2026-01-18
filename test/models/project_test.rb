require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "should have valid fixtures with credentials" do
    project = projects(:acme_web)
    setup_project_credentials(project)
    assert project.valid?

    project2 = projects(:acme_api)
    setup_project_credentials(project2)
    assert project2.valid?
  end

  test "should require name" do
    project = Project.new(
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "should require slug if name is blank" do
    project = Project.new(
      name: nil,  # No name means no auto-generated slug
      slug: nil,
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:slug], "can't be blank"
  end

  test "should require unique slug" do
    existing = projects(:acme_web)
    project = Project.new(
      name: "Different Name",
      slug: existing.slug,
      github_repository: "owner/different",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:slug], "has already been taken"
  end

  test "should validate slug format" do
    project = Project.new(
      name: "Test",
      slug: "Invalid_Slug!",
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:slug], "is invalid"
  end

  test "should accept valid slug format" do
    project = Project.new(
      name: "Test",
      slug: "valid-slug-123",
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert project.valid?
  end

  test "should require github_repository" do
    project = Project.new(
      name: "Test",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:github_repository], "can't be blank"
  end

  test "should validate github_repository format" do
    project = Project.new(
      name: "Test",
      slug: "test",
      github_repository: "invalid-format",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert_not project.valid?
    assert_includes project.errors[:github_repository], "is invalid"
  end

  test "should accept valid github_repository format" do
    project = Project.new(
      name: "Test",
      slug: "test",
      github_repository: "owner-name/repo-name",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    assert project.valid?
  end

  test "should have many users through project_memberships" do
    acme_web = projects(:acme_web)
    assert_includes acme_web.users, users(:alice)
    assert_includes acme_web.users, users(:bob)
    assert_includes acme_web.users, users(:charlie)
    assert_equal 3, acme_web.users.count
  end

  test "should have many project_memberships" do
    acme_web = projects(:acme_web)
    assert_equal 3, acme_web.project_memberships.count
  end

  test "should have many webhook_events" do
    acme_web = projects(:acme_web)
    assert_equal 2, acme_web.webhook_events.count
  end

  test "should destroy dependent associations" do
    skip "Ralph tables not set up in test database yet"
    project = projects(:acme_web)
    membership_count = project.project_memberships.count
    webhook_count = project.webhook_events.count

    assert membership_count > 0
    assert webhook_count > 0

    assert_difference "ProjectMembership.count", -membership_count do
      assert_difference "WebhookEvent.count", -webhook_count do
        project.destroy
      end
    end
  end

  test "should auto-generate slug on create" do
    project = Project.new(
      name: "Test Project Name",
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    project.save!
    assert_equal "test-project-name", project.slug
  end

  test "should not override provided slug" do
    project = Project.new(
      name: "Test Project Name",
      slug: "custom-slug",
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: "secret",
      anthropic_api_key: "key"
    )
    project.save!
    assert_equal "custom-slug", project.slug
  end

  test "should generate webhook secret after create" do
    project = Project.create!(
      name: "Test",
      slug: "test-webhook-gen",
      github_repository: "owner/repo",
      github_token: "token",
      anthropic_api_key: "key"
    )
    assert_not_nil project.github_webhook_secret
    assert project.github_webhook_secret.length > 20
  end

  test "should not override provided webhook secret" do
    custom_secret = "my_custom_secret_123"
    project = Project.create!(
      name: "Test",
      slug: "test-custom-secret",
      github_repository: "owner/repo",
      github_token: "token",
      github_webhook_secret: custom_secret,
      anthropic_api_key: "key"
    )
    assert_equal custom_secret, project.github_webhook_secret
  end

  test "should encrypt github_token" do
    project = projects(:acme_web)
    setup_project_credentials(project)

    token = "ghp_secret_token_123"
    project.update!(github_token: token)

    # Ciphertext should be different from plaintext
    assert_not_equal token, project.github_token_ciphertext

    # Should decrypt correctly
    assert_equal token, project.github_token
  end

  test "should encrypt github_webhook_secret" do
    project = projects(:acme_web)
    setup_project_credentials(project)

    secret = "webhook_secret_123"
    project.update!(github_webhook_secret: secret)

    # Ciphertext should be different from plaintext
    assert_not_equal secret, project.github_webhook_secret_ciphertext

    # Should decrypt correctly
    assert_equal secret, project.github_webhook_secret
  end

  test "should encrypt anthropic_api_key" do
    project = projects(:acme_web)
    setup_project_credentials(project)

    key = "sk-ant-api-key-123"
    project.update!(anthropic_api_key: key)

    # Ciphertext should be different from plaintext
    assert_not_equal key, project.anthropic_api_key_ciphertext

    # Should decrypt correctly
    assert_equal key, project.anthropic_api_key
  end

  test "configure_ralph! should set Ralph configuration" do
    project = projects(:acme_web)
    setup_project_credentials(project)
    project.configure_ralph!

    assert_equal project.github_token, Ralph.configuration.github_token
    assert_equal project.anthropic_api_key, Ralph.configuration.claude_api_key
    assert_equal project.github_repository, Ralph.configuration.repository
  end

  test "should scope active projects" do
    active_count = Project.where(active: true).count
    assert active_count > 0

    inactive_count = Project.where(active: false).count
    assert inactive_count > 0

    assert projects(:acme_web).active?
    assert_not projects(:inactive_project).active?
  end
end

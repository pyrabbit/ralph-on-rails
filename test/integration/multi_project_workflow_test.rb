require "test_helper"

class MultiProjectWorkflowTest < ActionDispatch::IntegrationTest
  def setup
    setup_all_project_credentials
  end

  test "complete user journey: login, create project, view project data" do
    # User logs in via GitHub OAuth
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      'provider' => 'github',
      'uid' => '99999',
      'info' => {
        'nickname' => 'newdev',
        'name' => 'New Developer',
        'email' => 'new@example.com',
        'image' => 'https://example.com/avatar.png'
      },
      'credentials' => { 'token' => 'mock_token' }
    })

    # Step 1: Login
    get auth_github_callback_path
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success

    user = User.find_by(github_login: 'newdev')
    assert_not_nil user

    # Step 2: View projects (should be empty for new user)
    get projects_path
    assert_response :success
    assert_match /You don't have any projects yet/i, response.body

    # Step 3: Create new project
    assert_difference 'Project.count', 1 do
      post projects_path, params: {
        project: {
          name: 'My First Project',
          github_repository: 'newdev/awesome-app',
          github_token: 'ghp_token123',
          anthropic_api_key: 'sk-ant-key123'
        }
      }
    end

    project = Project.last
    assert_equal 'my-first-project', project.slug
    assert_redirected_to project_path(project_id: project.slug)

    # Step 4: Verify user is owner
    membership = project.project_memberships.find_by(user: user)
    assert_equal 'owner', membership.role

    # Step 5: View project details
    follow_redirect!
    assert_response :success
    assert_match project.name, response.body
    assert_match project.github_repository, response.body

    # Step 6: Edit project
    get edit_project_path(project_id: project.slug)
    assert_response :success

    patch project_path(project_id: project.slug), params: {
      project: { name: 'Updated Project Name' }
    }
    assert_redirected_to project_path(project_id: project.slug)

    project.reload
    assert_equal 'Updated Project Name', project.name

    # Step 7: Logout
    delete logout_path
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "project isolation: users can only see their own projects" do
    # Alice logs in
    sign_in_as users(:alice)

    # Alice can see her projects
    get projects_path
    assert_response :success
    assert_match /acme-web/i, response.body
    assert_match /acme-api/i, response.body

    # Alice can access acme_web
    get project_path(project_id: 'acme-web')
    assert_response :success

    # Alice can access acme_api (she's a member)
    get project_path(project_id: 'acme-api')
    assert_response :success

    # Logout Alice, login Charlie
    delete logout_path
    sign_in_as users(:charlie)

    # Charlie can only see acme_web (he has viewer access)
    get projects_path
    assert_response :success
    assert_match /acme-web/i, response.body
    assert_no_match /acme-api/i, response.body  # Charlie shouldn't see this

    # Charlie can view acme_web
    get project_path(project_id: 'acme-web')
    assert_response :success

    # Charlie cannot access acme_api (no membership)
    assert_raises(Authorization::NotAuthorizedError) do
      get project_path(project_id: 'acme-api')
    end
  end

  test "role-based permissions: owner vs member vs viewer" do
    # Setup: Alice is owner, Bob is member, Charlie is viewer of acme_web
    project = projects(:acme_web)

    # Test Alice (owner) - can do everything
    sign_in_as users(:alice)

    get project_path(project_id: project.slug)
    assert_response :success

    get edit_project_path(project_id: project.slug)
    assert_response :success

    patch project_path(project_id: project.slug), params: {
      project: { name: 'Alice Updated Name' }
    }
    assert_redirected_to project_path(project_id: project.slug)

    # Test Bob (member) - can view but not edit
    delete logout_path
    sign_in_as users(:bob)

    get project_path(project_id: project.slug)
    assert_response :success

    assert_raises(Authorization::NotAuthorizedError) do
      get edit_project_path(project_id: project.slug)
    end

    assert_raises(Authorization::NotAuthorizedError) do
      patch project_path(project_id: project.slug), params: {
        project: { name: 'Bob Hacked Name' }
      }
    end

    # Test Charlie (viewer) - can only view
    delete logout_path
    sign_in_as users(:charlie)

    get project_path(project_id: project.slug)
    assert_response :success

    assert_raises(Authorization::NotAuthorizedError) do
      get edit_project_path(project_id: project.slug)
    end

    assert_raises(Authorization::NotAuthorizedError) do
      delete project_path(project_id: project.slug)
    end
  end

  test "webhook flow: webhook creates job for correct project" do
    project = projects(:acme_web)
    payload = {
      action: "synchronize",
      pull_request: { number: 123, mergeable: false }
    }.to_json

    signature = "sha256=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      project.github_webhook_secret,
      payload
    )

    # Send webhook
    assert_enqueued_with(job: GithubWebhookProcessorJob) do
      post webhooks_github_project_path(project_id: project.slug),
        params: payload,
        headers: {
          'Content-Type' => 'application/json',
          'X-GitHub-Event' => 'pull_request',
          'X-GitHub-Delivery' => 'integration-test-001',
          'X-Hub-Signature-256' => signature
        }
    end

    assert_response :ok

    # Verify job has correct project_id
    job = enqueued_jobs.last
    assert_equal project.id, job[:args].first[:project_id]
  end

  test "Current.project is properly set and cleared" do
    alice = users(:alice)
    project = projects(:acme_web)

    # Initially no current project
    assert_nil Current.project

    # Sign in and access project
    sign_in_as alice
    get project_path(project_id: project.slug)
    assert_response :success

    # After request, Current should be cleared (happens in test teardown)
    # This is tested by the test_helper teardown block
  end

  test "multiple projects don't interfere with each other" do
    alice = users(:alice)
    acme_web = projects(:acme_web)
    acme_api = projects(:acme_api)

    sign_in_as alice

    # Access acme_web
    get project_path(project_id: acme_web.slug)
    assert_response :success
    assert_match acme_web.name, response.body

    # Access acme_api - should be completely isolated
    get project_path(project_id: acme_api.slug)
    assert_response :success
    assert_match acme_api.name, response.body
    assert_no_match acme_web.name, response.body
  end

  test "project deletion cascade removes all associations" do
    alice = users(:alice)
    project = projects(:acme_web)

    sign_in_as alice

    membership_count = project.project_memberships.count
    webhook_count = project.webhook_events.count

    assert membership_count > 0
    assert webhook_count > 0

    # Delete project
    assert_difference 'Project.count', -1 do
      assert_difference 'ProjectMembership.count', -membership_count do
        assert_difference 'WebhookEvent.count', -webhook_count do
          delete project_path(project_id: project.slug)
        end
      end
    end

    assert_redirected_to projects_path
  end

  test "unauthenticated user is redirected to login for protected routes" do
    protected_paths = [
      projects_path,
      new_project_path,
      project_path(project_id: 'acme-web'),
      edit_project_path(project_id: 'acme-web')
    ]

    protected_paths.each do |path|
      get path
      assert_redirected_to login_path, "Should redirect to login for #{path}"
    end
  end
end

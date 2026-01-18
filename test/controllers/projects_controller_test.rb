require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  def setup
    setup_all_project_credentials
  end

  # Index action tests
  test "should get index when authenticated" do
    sign_in_as users(:alice)
    get projects_path
    assert_response :success
    assert_select 'h1', text: /Projects/i
  end

  test "should redirect to login when not authenticated" do
    get projects_path
    assert_redirected_to login_path
    assert_equal 'Please sign in to continue', flash[:alert]
  end

  test "should only show user's projects in index" do
    sign_in_as users(:alice)
    get projects_path
    assert_response :success

    # Alice should see acme_web and acme_api
    assert_match /acme-web/i, response.body
    assert_match /acme-api/i, response.body

    # Should not see inactive project (Alice has no membership)
    assert_no_match /inactive-project/i, response.body
  end

  # New action tests
  test "should get new when authenticated" do
    sign_in_as users(:alice)
    get new_project_path
    assert_response :success
    assert_select 'form'
  end

  test "should not get new when unauthenticated" do
    get new_project_path
    assert_redirected_to login_path
  end

  # Create action tests
  test "should create project when authenticated" do
    sign_in_as users(:alice)

    assert_difference 'Project.count', 1 do
      assert_difference 'ProjectMembership.count', 1 do
        post projects_path, params: {
          project: {
            name: 'New Test Project',
            github_repository: 'test-org/test-repo',
            github_token: 'ghp_test_token',
            anthropic_api_key: 'sk-ant-test-key'
          }
        }
      end
    end

    project = Project.last
    assert_equal 'New Test Project', project.name
    assert_equal 'new-test-project', project.slug
    assert_redirected_to project_path(project_id: project.slug)

    # Verify creator is set as owner
    membership = project.project_memberships.find_by(user: users(:alice))
    assert_not_nil membership
    assert_equal 'owner', membership.role
  end

  test "should not create project when unauthenticated" do
    assert_no_difference 'Project.count' do
      post projects_path, params: {
        project: {
          name: 'New Project',
          github_repository: 'test/repo',
          github_token: 'token',
          anthropic_api_key: 'key'
        }
      }
    end

    assert_redirected_to login_path
  end

  test "should handle validation errors on create" do
    sign_in_as users(:alice)

    assert_no_difference 'Project.count' do
      post projects_path, params: {
        project: {
          name: '',  # Invalid: blank name
          github_repository: 'test/repo',
          github_token: 'token',
          anthropic_api_key: 'key'
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # Show action tests
  test "should show project when user has access" do
    sign_in_as users(:alice)
    project = projects(:acme_web)

    get project_path(project_id: project.slug)
    assert_response :success
    assert_match project.name, response.body
  end

  test "should not show project when user has no access" do
    sign_in_as users(:charlie)
    project = projects(:acme_api)  # Charlie has no access to acme_api

    assert_raises(Authorization::NotAuthorizedError) do
      get project_path(project_id: project.slug)
    end
  end

  test "should return 404 for nonexistent project" do
    sign_in_as users(:alice)
    get project_path(project_id: 'nonexistent-slug')
    assert_redirected_to projects_path
    assert_equal 'Project not found', flash[:alert]
  end

  # Edit action tests
  test "should get edit when user is owner" do
    sign_in_as users(:alice)  # Alice is owner of acme_web
    project = projects(:acme_web)

    get edit_project_path(project_id: project.slug)
    assert_response :success
    assert_select 'form'
  end

  test "should not get edit when user is not owner" do
    sign_in_as users(:bob)  # Bob is only member of acme_web
    project = projects(:acme_web)

    assert_raises(Authorization::NotAuthorizedError) do
      get edit_project_path(project_id: project.slug)
    end
  end

  # Update action tests
  test "should update project when user is owner" do
    sign_in_as users(:alice)
    project = projects(:acme_web)

    patch project_path(project_id: project.slug), params: {
      project: {
        name: 'Updated Project Name'
      }
    }

    assert_redirected_to project_path(project_id: project.slug)
    project.reload
    assert_equal 'Updated Project Name', project.name
  end

  test "should not update project when user is not owner" do
    sign_in_as users(:bob)  # Bob is member, not owner
    project = projects(:acme_web)

    assert_raises(Authorization::NotAuthorizedError) do
      patch project_path(project_id: project.slug), params: {
        project: { name: 'Hacked Name' }
      }
    end

    project.reload
    assert_not_equal 'Hacked Name', project.name
  end

  test "should handle validation errors on update" do
    sign_in_as users(:alice)
    project = projects(:acme_web)

    patch project_path(project_id: project.slug), params: {
      project: {
        name: '',  # Invalid: blank name
        github_token: 'valid_token'
      }
    }

    assert_response :unprocessable_entity
  end

  # Destroy action tests
  test "should destroy project when user is owner" do
    sign_in_as users(:alice)
    project = projects(:acme_web)

    assert_difference 'Project.count', -1 do
      delete project_path(project_id: project.slug)
    end

    assert_redirected_to projects_path
    assert_equal 'Project was successfully deleted', flash[:notice]
  end

  test "should not destroy project when user is not owner" do
    sign_in_as users(:bob)  # Bob is member, not owner
    project = projects(:acme_web)

    assert_raises(Authorization::NotAuthorizedError) do
      assert_no_difference 'Project.count' do
        delete project_path(project_id: project.slug)
      end
    end
  end
end

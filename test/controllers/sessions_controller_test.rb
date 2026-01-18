require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new login page" do
    get login_path
    assert_response :success
  end

  test "should redirect to GitHub OAuth on create via GET" do
    get auth_github_callback_path
    # Without OmniAuth data, controller will try to process and redirect
    assert_redirected_to projects_path
  end

  test "should create session on successful GitHub OAuth callback" do
    # Mock OmniAuth auth hash
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
        'token' => 'mock_github_token'
      }
    })

    assert_difference 'User.count', 1 do
      get auth_github_callback_path
    end

    assert_redirected_to projects_path
    assert session[:user_id].present?
    assert_match /Signed in as testuser/, flash[:notice]

    # Verify user was created with correct attributes
    user = User.find(session[:user_id])
    assert_equal 12345, user.github_id
    assert_equal 'testuser', user.github_login
    assert_equal 'Test User', user.github_name
  end

  test "should find existing user on OAuth callback" do
    existing_user = users(:alice)

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      'provider' => 'github',
      'uid' => existing_user.github_id.to_s,
      'info' => {
        'nickname' => existing_user.github_login,
        'name' => existing_user.github_name,
        'email' => existing_user.github_email,
        'image' => existing_user.github_avatar_url
      },
      'credentials' => {
        'token' => 'updated_token'
      }
    })

    assert_no_difference 'User.count' do
      get auth_github_callback_path
    end

    assert_redirected_to projects_path
    assert_equal existing_user.id, session[:user_id]
  end

  test "should handle OAuth failure gracefully" do
    get auth_failure_path
    assert_redirected_to root_path
    assert_match /Authentication failed/, flash[:alert]
  end

  test "should destroy session on logout" do
    # First authenticate properly via OmniAuth
    user = users(:alice)

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
        'token' => 'token'
      }
    })

    # Login
    get auth_github_callback_path
    assert_equal user.id, session[:user_id]

    # Now logout
    delete logout_path

    assert_nil session[:user_id]
    assert_redirected_to root_path
    assert_match /Signed out/, flash[:notice]
  end

  test "should redirect unauthenticated user to login" do
    # Try to access a protected page without being signed in
    get projects_path
    assert_redirected_to login_path
    assert_equal 'Please sign in to continue', flash[:alert]
  end
end

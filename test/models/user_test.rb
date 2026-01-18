require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "should have valid fixtures" do
    assert users(:alice).valid?
    assert users(:bob).valid?
    assert users(:charlie).valid?
  end

  test "should require github_id" do
    user = User.new(github_login: "test")
    assert_not user.valid?
    assert_includes user.errors[:github_id], "can't be blank"
  end

  test "should require github_login" do
    user = User.new(github_id: 9999)
    assert_not user.valid?
    assert_includes user.errors[:github_login], "can't be blank"
  end

  test "should require unique github_id" do
    existing_user = users(:alice)
    duplicate_user = User.new(
      github_id: existing_user.github_id,
      github_login: "different_login"
    )
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:github_id], "has already been taken"
  end

  test "should have many projects through project_memberships" do
    alice = users(:alice)
    assert_includes alice.projects, projects(:acme_web)
    assert_includes alice.projects, projects(:acme_api)
    assert_equal 2, alice.projects.count
  end

  test "should have many project_memberships" do
    alice = users(:alice)
    assert_equal 2, alice.project_memberships.count
  end

  test "should destroy dependent project_memberships" do
    alice = users(:alice)
    membership_count = alice.project_memberships.count
    assert membership_count > 0

    assert_difference "ProjectMembership.count", -membership_count do
      alice.destroy
    end
  end

  test "find_or_create_from_github should create new user" do
    auth_hash = {
      "uid" => "999999",
      "info" => {
        "nickname" => "newuser",
        "name" => "New User",
        "email" => "new@example.com",
        "image" => "https://example.com/avatar.png"
      },
      "credentials" => {
        "token" => "gho_newtoken123"
      }
    }

    assert_difference "User.count", 1 do
      user = User.find_or_create_from_github(auth_hash)
      assert_equal 999999, user.github_id
      assert_equal "newuser", user.github_login
      assert_equal "New User", user.github_name
      assert_equal "new@example.com", user.github_email
    end
  end

  test "find_or_create_from_github should find existing user" do
    existing_user = users(:alice)
    auth_hash = {
      "uid" => existing_user.github_id.to_s,
      "info" => {
        "nickname" => existing_user.github_login,
        "name" => existing_user.github_name,
        "email" => existing_user.github_email,
        "image" => existing_user.github_avatar_url
      },
      "credentials" => {
        "token" => "updated_token"
      }
    }

    assert_no_difference "User.count" do
      user = User.find_or_create_from_github(auth_hash)
      assert_equal existing_user.id, user.id
    end
  end

  test "should encrypt github_access_token" do
    user = users(:alice)
    user.update!(github_access_token: "secret_token_123")

    # The ciphertext should be different from plaintext
    assert_not_equal "secret_token_123", user.github_access_token_ciphertext

    # Should decrypt correctly
    assert_equal "secret_token_123", user.github_access_token
  end
end

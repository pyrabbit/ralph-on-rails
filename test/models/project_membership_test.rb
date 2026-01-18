require "test_helper"

class ProjectMembershipTest < ActiveSupport::TestCase
  test "should have valid fixtures" do
    assert project_memberships(:alice_acme_web_owner).valid?
    assert project_memberships(:bob_acme_api_owner).valid?
    assert project_memberships(:charlie_acme_web_viewer).valid?
  end

  test "should require user" do
    membership = ProjectMembership.new(
      project: projects(:acme_web),
      role: "member"
    )
    assert_not membership.valid?
    assert_includes membership.errors[:user], "must exist"
  end

  test "should require project" do
    membership = ProjectMembership.new(
      user: users(:alice),
      role: "member"
    )
    assert_not membership.valid?
    assert_includes membership.errors[:project], "must exist"
  end

  test "should require role" do
    membership = ProjectMembership.new(
      user: users(:alice),
      project: projects(:acme_web),
      role: nil
    )
    assert_not membership.valid?
    assert_includes membership.errors[:role], "can't be blank"
  end

  test "should default to viewer role" do
    membership = ProjectMembership.create!(
      user: users(:alice),
      project: projects(:inactive_project)
    )
    assert_equal "viewer", membership.role
  end

  test "should require unique user-project combination" do
    existing = project_memberships(:alice_acme_web_owner)
    duplicate = ProjectMembership.new(
      user: existing.user,
      project: existing.project,
      role: "member"
    )
    assert_not duplicate.valid?
  end

  test "should allow same user in different projects" do
    alice = users(:alice)
    assert_equal 2, alice.project_memberships.count
    assert alice.projects.include?(projects(:acme_web))
    assert alice.projects.include?(projects(:acme_api))
  end

  test "should allow different users in same project with different roles" do
    acme_web = projects(:acme_web)
    memberships = acme_web.project_memberships

    alice_membership = memberships.find_by(user: users(:alice))
    bob_membership = memberships.find_by(user: users(:bob))
    charlie_membership = memberships.find_by(user: users(:charlie))

    assert_equal "owner", alice_membership.role
    assert_equal "member", bob_membership.role
    assert_equal "viewer", charlie_membership.role
  end

  test "should validate role values" do
    valid_roles = %w[viewer member owner]
    valid_roles.each do |role|
      membership = ProjectMembership.new(
        user: users(:alice),
        project: projects(:inactive_project),
        role: role
      )
      assert membership.valid?, "#{role} should be valid"
    end
  end

  test "role_hierarchy should return correct numeric value" do
    assert_equal 0, ProjectMembership.new(role: "viewer").role_hierarchy
    assert_equal 1, ProjectMembership.new(role: "member").role_hierarchy
    assert_equal 2, ProjectMembership.new(role: "owner").role_hierarchy
  end

  test "has_role_level? should check role hierarchy" do
    owner = project_memberships(:alice_acme_web_owner)
    member = project_memberships(:bob_acme_web_member)
    viewer = project_memberships(:charlie_acme_web_viewer)

    # Owner has all levels
    assert owner.has_role_level?(:viewer)
    assert owner.has_role_level?(:member)
    assert owner.has_role_level?(:owner)

    # Member has viewer and member
    assert member.has_role_level?(:viewer)
    assert member.has_role_level?(:member)
    assert_not member.has_role_level?(:owner)

    # Viewer only has viewer
    assert viewer.has_role_level?(:viewer)
    assert_not viewer.has_role_level?(:member)
    assert_not viewer.has_role_level?(:owner)
  end

  test "owner? should return true for owner role" do
    assert project_memberships(:alice_acme_web_owner).owner?
    assert_not project_memberships(:bob_acme_web_member).owner?
    assert_not project_memberships(:charlie_acme_web_viewer).owner?
  end

  test "member? should return true for member role" do
    assert_not project_memberships(:alice_acme_web_owner).member?
    assert project_memberships(:bob_acme_web_member).member?
    assert_not project_memberships(:charlie_acme_web_viewer).member?
  end

  test "viewer? should return true for viewer role" do
    assert_not project_memberships(:alice_acme_web_owner).viewer?
    assert_not project_memberships(:bob_acme_web_member).viewer?
    assert project_memberships(:charlie_acme_web_viewer).viewer?
  end
end

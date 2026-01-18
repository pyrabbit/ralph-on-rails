# frozen_string_literal: true

module AuthorizationHelper
  def can_manage_project_for?(project)
    return false unless Current.user
    membership = project.project_memberships.find_by(user: Current.user)
    membership&.owner?
  end

  def can_modify_project_for?(project)
    return false unless Current.user
    membership = project.project_memberships.find_by(user: Current.user)
    membership&.owner? || membership&.member?
  end

  def can_view_project?(project)
    return false unless Current.user
    project.project_memberships.exists?(user: Current.user)
  end
end

# frozen_string_literal: true

module Authorization
  extend ActiveSupport::Concern

  class NotAuthorizedError < StandardError; end

  included do
    rescue_from NotAuthorizedError, with: :handle_unauthorized
  end

  private

  def authorize_project_access!(required_role = :viewer)
    unless can_access_project?(Current.project, required_role)
      raise NotAuthorizedError
    end
  end

  def can_access_project?(project, required_role = :viewer)
    return false unless Current.user
    return false unless project

    membership = project.project_memberships.find_by(user: Current.user)
    return false unless membership

    role_hierarchy = { viewer: 0, member: 1, owner: 2 }
    role_hierarchy[membership.role.to_sym] >= role_hierarchy[required_role]
  end

  def current_membership
    @current_membership ||= Current.project&.project_memberships&.find_by(user: Current.user)
  end

  def can_manage_project?
    current_membership&.owner?
  end

  def can_modify_project?
    current_membership&.owner? || current_membership&.member?
  end

  def handle_unauthorized
    redirect_to projects_path, alert: "You don't have permission to access this project"
  end
end

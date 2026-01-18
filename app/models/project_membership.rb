# frozen_string_literal: true

class ProjectMembership < ApplicationRecord
  belongs_to :user
  belongs_to :project

  # Role enum: viewer (read-only), member (can trigger actions), owner (full access)
  enum :role, { viewer: 'viewer', member: 'member', owner: 'owner' }, default: :viewer

  validates :user_id, uniqueness: { scope: :project_id }
  validates :role, presence: true

  # Ensure exactly one owner per project
  validate :only_one_owner_per_project, if: :owner?

  # Role hierarchy for authorization checks
  ROLE_HIERARCHY = { viewer: 0, member: 1, owner: 2 }.freeze

  def role_hierarchy
    ROLE_HIERARCHY[role.to_sym]
  end

  def has_role_level?(required_role)
    role_hierarchy >= ROLE_HIERARCHY[required_role]
  end

  private

  def only_one_owner_per_project
    if project.project_memberships.where(role: 'owner').where.not(id: id).exists?
      errors.add(:role, 'project can only have one owner')
    end
  end
end

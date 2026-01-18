# frozen_string_literal: true

class Project < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
  has_many :webhook_events, dependent: :destroy

  # Ralph associations (will have project_id foreign key)
  has_many :issue_assignments, class_name: 'Ralph::IssueAssignment', dependent: :destroy
  has_many :pull_requests, class_name: 'Ralph::PullRequest', dependent: :destroy
  has_many :design_documents, class_name: 'Ralph::DesignDocument', dependent: :destroy

  encrypts :github_token
  encrypts :github_webhook_secret
  encrypts :anthropic_api_key

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :github_repository, presence: true, uniqueness: true, format: { with: /\A[\w-]+\/[\w-]+\z/ }
  validates :github_token, presence: true
  validates :anthropic_api_key, presence: true
  # github_webhook_secret is auto-generated in after_create callback if not provided

  before_validation :generate_slug, on: :create
  after_create :generate_webhook_secret, unless: :github_webhook_secret?

  def owner
    project_memberships.find_by(role: 'owner')&.user
  end

  def configure_ralph!
    Ralph.configure do |config|
      config.github_token = github_token
      config.claude_api_key = anthropic_api_key
      config.repository = github_repository
    end
  end

  def issue_assignments_count
    @issue_assignments_count ||= issue_assignments.count
  end

  def pull_requests_count
    @pull_requests_count ||= pull_requests.count
  end

  private

  def generate_slug
    return if slug.present? || name.blank?

    base_slug = name.parameterize
    candidate = base_slug
    counter = 1

    while Project.exists?(slug: candidate)
      candidate = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate
  end

  def generate_webhook_secret
    self.github_webhook_secret = SecureRandom.hex(32)
    save
  end
end

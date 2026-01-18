# frozen_string_literal: true

class User < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships

  encrypts :github_access_token

  validates :github_id, presence: true, uniqueness: true
  validates :github_login, presence: true

  def self.find_or_create_from_github(auth)
    find_or_create_by(github_id: auth['uid']) do |user|
      user.github_login = auth['info']['nickname']
      user.github_name = auth['info']['name']
      user.github_email = auth['info']['email']
      user.github_avatar_url = auth['info']['image']
      user.github_access_token = auth['credentials']['token']
    end
  end
end

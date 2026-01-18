class AddUniqueIndexToProjectsGithubRepository < ActiveRecord::Migration[8.1]
  def change
    # Remove existing non-unique index if it exists
    remove_index :projects, :github_repository if index_exists?(:projects, :github_repository)

    # Add unique index
    add_index :projects, :github_repository, unique: true
  end
end

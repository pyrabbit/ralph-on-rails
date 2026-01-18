module Ralph
  class Base < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = "ralph_"

    # All Ralph models belong to a project
    belongs_to :project

    # Automatically scope all queries to current project
    default_scope { where(project_id: Current.project&.id) if Current.project }

    # Make records readonly (Ralph data is managed by Ralph gem)
    def readonly?
      true
    end

    # Temporarily disable project scoping (use with caution!)
    def self.unscoped_by_project
      unscoped { yield }
    end
  end
end

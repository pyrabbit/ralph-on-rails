# frozen_string_literal: true

# Ralph initializer for Rails applications
#
# This is a multi-project setup where Ralph is configured dynamically
# per-project via Current.project= (see app/models/current.rb)
# Each project has its own encrypted credentials in the database.

Ralph.logger = Rails.logger

# Note: Ralph configuration is loaded dynamically when Current.project is set.
# See Current#project= in app/models/current.rb which calls project.configure_ralph!
Rails.logger.info "Ralph initialized (multi-project mode - configuration per project)"

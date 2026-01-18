# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :project

  def user=(user)
    super
    Time.zone = user&.time_zone if user&.respond_to?(:time_zone) && user.time_zone
  end

  def project=(project)
    super
    # Configure Ralph when project is set
    project&.configure_ralph!
  end
end

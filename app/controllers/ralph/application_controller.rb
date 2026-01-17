module Ralph
  class ApplicationController < ::ApplicationController
    # Explicitly add route helpers to views
    helper do
      include Rails.application.routes.url_helpers
    end
  end
end

class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include ProjectScoping

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication

  # Allow unauthenticated access to home page
  def home
    if authenticated?
      redirect_to projects_path
    else
      render 'pages/home'
    end
  end
end

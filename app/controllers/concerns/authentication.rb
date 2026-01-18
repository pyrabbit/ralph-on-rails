# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
  end

  private

  def set_current_user
    if session[:user_id]
      Current.user = User.find_by(id: session[:user_id])
    end
  end

  def require_authentication
    unless Current.user
      redirect_to login_path, alert: "Please sign in to continue"
    end
  end

  def authenticated?
    Current.user.present?
  end
end

# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :create, :failure]

  def new
    # Login page with "Sign in with GitHub" button
  end

  def create
    # OmniAuth callback
    auth = request.env['omniauth.auth']
    user = User.find_or_create_from_github(auth)

    session[:user_id] = user.id
    redirect_to projects_path, notice: "Signed in as #{user.github_login}"
  end

  def destroy
    session[:user_id] = nil
    Current.user = nil
    redirect_to root_path, notice: "Signed out"
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message]}"
  end
end

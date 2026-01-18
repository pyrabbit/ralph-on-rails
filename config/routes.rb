Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root
  root to: 'application#home'

  # Authentication
  get 'login', to: 'sessions#new'
  get 'auth/github/callback', to: 'sessions#create'
  post 'auth/github/callback', to: 'sessions#create' # POST for CSRF protection
  get 'auth/failure', to: 'sessions#failure'
  delete 'logout', to: 'sessions#destroy'

  # Projects management (not scoped to specific project)
  resources :projects, only: [:index, :new, :create]

  # Project-scoped routes
  scope ':project_id' do
    # Project settings and management
    resource :project, only: [:show, :edit, :update, :destroy], controller: 'projects' do
      resources :members, only: [:index, :create, :destroy], controller: 'project_members'
      get 'webhook', to: 'projects#webhook_info'
    end

    # Ralph data viewers (existing routes, now project-scoped)
    namespace :ralph do
      root to: 'home#index'
      resources :issue_assignments, only: [:index, :show] do
        member do
          post :toggle_design_approved
        end
      end
      resources :models, only: [:index, :show]
    end
  end

  # Webhooks (project-specific, not authenticated)
  namespace :webhooks do
    post 'github/:project_id', to: 'github#create', as: :github_project
  end
end

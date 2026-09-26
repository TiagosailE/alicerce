Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[show create destroy] do
        resource :organization, only: :create, controller: "sessions/organizations"
      end
      resources :audit_events, only: :index
      resources :units, only: %i[index show create update]
      resources :categories, only: %i[index show create update]
      resources :products, only: %i[index show create update]
      resources :warehouses, only: %i[index show create update]
      resources :stock_balances, only: :index
      resources :stock_movements, only: :index
      resources :stock_adjustments, only: :create
      resources :partners, only: %i[index show create update]
      resources :purchase_orders, only: %i[index show create update] do
        scope module: :purchase_orders do
          resource :approval, only: :create
          resource :cancellation, only: :create
        end
      end
      resources :invitations, only: %i[create index destroy]
      # The token is the credential; it travels in the body, never the URL
      # (a security review of the password reset routes below found that
      # Rails logs the raw request path unfiltered, which would leak it).
      post "invitations/acceptance", to: "invitations/acceptances#create", as: :invitation_acceptance
      resources :memberships, only: %i[index update destroy]
      resources :password_resets, only: :create
      post "password_resets/completion", to: "password_resets/completions#create", as: :password_reset_completion
      resource :password, only: :update, controller: "passwords"
    end
  end

  # Any /api path that matched none of the routes above answers the JSON
  # error envelope, never the SPA shell or a bare routing error.
  match "/api", to: "api/v1/base#route_not_found", via: :all
  match "/api/*unmatched", to: "api/v1/base#route_not_found", via: :all

  spa_page = lambda do |request|
    request.format.html? && File.extname(request.path).empty? && !request.path.match?(%r{\A/(api|spa)(/|\z)})
  end

  get "theme-init.js", to: "spa#theme_init"

  root "spa#show"
  get "*path", to: "spa#show", format: false, constraints: spa_page
end

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[show create destroy] do
        resource :organization, only: :create, controller: "sessions/organizations"
      end
      resources :audit_events, only: :index
      resources :invitations, only: :create
      post "invitations/:token/acceptance", to: "invitations/acceptances#create", as: :invitation_acceptance
      resources :memberships, only: %i[update destroy]
    end
  end

  # Any /api path that matched none of the routes above answers the JSON
  # error envelope, never the SPA shell or a bare routing error.
  match "/api", to: "api/v1/base#route_not_found", via: :all
  match "/api/*unmatched", to: "api/v1/base#route_not_found", via: :all

  spa_page = lambda do |request|
    request.format.html? && File.extname(request.path).empty? && !request.path.match?(%r{\A/(api|spa)(/|\z)})
  end

  root "spa#show"
  get "*path", to: "spa#show", format: false, constraints: spa_page
end

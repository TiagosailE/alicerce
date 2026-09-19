Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "spa#show"
  get "*path", to: "spa#show", format: false, constraints: ->(request) { !request.path.start_with?("/api/", "/spa/") }
end

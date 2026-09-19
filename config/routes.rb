Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  spa_page = lambda do |request|
    request.format.html? && File.extname(request.path).empty? && !request.path.match?(%r{\A/(api|spa)(/|\z)})
  end

  root "spa#show"
  get "*path", to: "spa#show", format: false, constraints: spa_page
end

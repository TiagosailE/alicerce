module SessionHelpers
  def fetch_csrf_token
    get "/api/v1/session"
    response.parsed_body.dig("data", "csrf_token")
  end

  def sign_in_via_api(email:, password:, organization_id: nil, csrf_token: fetch_csrf_token)
    post "/api/v1/session",
      params: { email:, password:, organization_id: }.compact,
      as: :json,
      headers: { "X-CSRF-Token" => csrf_token }
  end
end

RSpec.configure do |config|
  config.include SessionHelpers, type: :request
end

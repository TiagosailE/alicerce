require "rails_helper"

# Fails the moment a future /api/v1 route ships with no isolation or role
# matrix entry, per the testing-strategy skill. The session endpoints are
# exempt (ADR 0008, see Api::V1::SessionsController); every other route
# names the spec that proves it belongs in each matrix.
RSpec.describe "API route inventory" do
  EXEMPT_ROUTES = %w[
    api/v1/sessions#show
    api/v1/sessions#create
    api/v1/sessions#destroy
    api/v1/sessions/organizations#create
    api/v1/base#route_not_found
  ].freeze

  ISOLATION_MATRIX = {
    "api/v1/audit_events#index" => "spec/requests/api/v1/audit_events_spec.rb, another organization's events never appear"
  }.freeze

  ROLE_MATRIX = {
    "api/v1/audit_events#index" => "spec/requests/api/v1/audit_events_spec.rb, one example per role"
  }.freeze

  it "has an isolation matrix entry for every /api/v1 route, or an explicit exemption" do
    missing = RouteInventory.missing_from(ISOLATION_MATRIX, exempt: EXEMPT_ROUTES).map { |route| route[:key] }

    expect(missing).to be_empty, "add an isolation matrix entry (or exempt, with a reason) for: #{missing.join(', ')}"
  end

  it "has a role matrix entry for every /api/v1 route, or an explicit exemption" do
    missing = RouteInventory.missing_from(ROLE_MATRIX, exempt: EXEMPT_ROUTES).map { |route| route[:key] }

    expect(missing).to be_empty, "add a role matrix entry (or exempt, with a reason) for: #{missing.join(', ')}"
  end
end

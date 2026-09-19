require "rails_helper"

# Fails the moment a future /api/v1 route ships with no isolation or role
# matrix entry, per the testing-strategy skill. Both matrices are still
# empty: nothing outside the session endpoints exists yet, and those are
# exempt (ADR 0008, see Api::V1::SessionsController).
RSpec.describe "API route inventory" do
  EXEMPT_ROUTES = %w[
    api/v1/sessions#show
    api/v1/sessions#create
    api/v1/sessions#destroy
    api/v1/sessions/organizations#create
    api/v1/base#route_not_found
  ].freeze

  ISOLATION_MATRIX = {}.freeze
  ROLE_MATRIX = {}.freeze

  it "has an isolation matrix entry for every /api/v1 route, or an explicit exemption" do
    missing = RouteInventory.missing_from(ISOLATION_MATRIX, exempt: EXEMPT_ROUTES).map { |route| route[:key] }

    expect(missing).to be_empty, "add an isolation matrix entry (or exempt, with a reason) for: #{missing.join(', ')}"
  end

  it "has a role matrix entry for every /api/v1 route, or an explicit exemption" do
    missing = RouteInventory.missing_from(ROLE_MATRIX, exempt: EXEMPT_ROUTES).map { |route| route[:key] }

    expect(missing).to be_empty, "add a role matrix entry (or exempt, with a reason) for: #{missing.join(', ')}"
  end
end

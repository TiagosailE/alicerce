require "rails_helper"

# Fails the moment a future /api/v1 route ships with no isolation or role
# matrix entry, per the testing-strategy skill. The session endpoints are
# exempt (ADR 0008, see Api::V1::SessionsController); so are the password
# reset endpoints, for the same reason as invitations/acceptances#create
# (no session exists yet, the token is the only credential); so is
# passwords#update, which only ever acts on Current.user (no id in the
# route, no other organization's record reachable, no per-role variance
# beyond the demo denial, see Api::V1::PasswordsController). Every other
# route names the spec that proves it belongs in each matrix.
RSpec.describe "API route inventory" do
  EXEMPT_ROUTES = %w[
    api/v1/sessions#show
    api/v1/sessions#create
    api/v1/sessions#destroy
    api/v1/sessions/organizations#create
    api/v1/base#route_not_found
    api/v1/invitations/acceptances#create
    api/v1/password_resets#create
    api/v1/password_resets/completions#create
    api/v1/passwords#update
  ].freeze

  ISOLATION_MATRIX = {
    "api/v1/audit_events#index" => "spec/requests/api/v1/audit_events_spec.rb, another organization's events never appear",
    "api/v1/units#index" => "spec/requests/api/v1/units_spec.rb, another organization's unit never appears",
    "api/v1/units#show" => "spec/requests/api/v1/units_spec.rb, another organization's unit answers not_found",
    "api/v1/units#create" => "spec/requests/api/v1/units_spec.rb, the unit is visible only to the current organization",
    "api/v1/units#update" => "spec/requests/api/v1/units_spec.rb, another organization's unit answers not_found and is unchanged",
    "api/v1/categories#index" => "spec/requests/api/v1/categories_spec.rb, another organization's category never appears",
    "api/v1/categories#show" => "spec/requests/api/v1/categories_spec.rb, another organization's category answers not_found",
    "api/v1/categories#create" => "spec/requests/api/v1/categories_spec.rb, the category is visible only to the current organization",
    "api/v1/categories#update" => "spec/requests/api/v1/categories_spec.rb, another organization's category answers not_found and is unchanged",
    "api/v1/products#index" => "spec/requests/api/v1/products_spec.rb, another organization's product never appears",
    "api/v1/products#show" => "spec/requests/api/v1/products_spec.rb, another organization's product answers not_found",
    "api/v1/products#create" => "spec/requests/api/v1/products_spec.rb, the product is visible only to the current organization",
    "api/v1/products#update" => "spec/requests/api/v1/products_spec.rb, another organization's product answers not_found and is unchanged",
    "api/v1/warehouses#index" => "spec/requests/api/v1/warehouses_spec.rb, another organization's warehouse never appears",
    "api/v1/warehouses#show" => "spec/requests/api/v1/warehouses_spec.rb, another organization's warehouse answers not_found",
    "api/v1/warehouses#create" => "spec/requests/api/v1/warehouses_spec.rb, the warehouse is visible only to the current organization",
    "api/v1/warehouses#update" => "spec/requests/api/v1/warehouses_spec.rb, another organization's warehouse answers not_found and is unchanged",
    "api/v1/stock_balances#index" => "spec/requests/api/v1/stock_balances_spec.rb, another organization's balance never appears",
    "api/v1/stock_movements#index" => "spec/requests/api/v1/stock_movements_spec.rb, another organization's movement never appears",
    "api/v1/stock_adjustments#create" => "spec/requests/api/v1/stock_adjustments_spec.rb, another organization's product or warehouse answers not_found and nothing is written",
    "api/v1/purchase_orders#index" => "spec/requests/api/v1/purchase_orders_spec.rb, another organization's order never appears",
    "api/v1/purchase_orders#show" => "spec/requests/api/v1/purchase_orders_spec.rb, another organization's order answers not_found",
    "api/v1/purchase_orders#create" => "spec/requests/api/v1/purchase_orders_spec.rb, the order is visible only to the current organization and another organization's supplier answers not_found",
    "api/v1/purchase_orders#update" => "spec/requests/api/v1/purchase_orders_spec.rb, another organization's order answers not_found and is unchanged",
    "api/v1/purchase_orders/approvals#create" => "spec/requests/api/v1/purchase_orders_spec.rb, another organization's order answers not_found and stays a draft",
    "api/v1/purchase_orders/cancellations#create" => "spec/requests/api/v1/purchase_orders_spec.rb, another organization's order answers not_found and stays a draft",
    "api/v1/purchase_orders/receipts#create" => "spec/requests/api/v1/receipts_spec.rb, another organization's order or warehouse answers not_found, another organization's order line answers not_found, and nothing is written",
    "api/v1/receipts#index" => "spec/requests/api/v1/receipts_spec.rb, another organization's receipt never appears",
    "api/v1/receipts#show" => "spec/requests/api/v1/receipts_spec.rb, another organization's receipt answers not_found",
    "api/v1/payables#index" => "spec/requests/api/v1/payables_spec.rb, another organization's payable never appears",
    "api/v1/partners#index" => "spec/requests/api/v1/partners_spec.rb, another organization's partner never appears",
    "api/v1/partners#show" => "spec/requests/api/v1/partners_spec.rb, another organization's partner answers not_found",
    "api/v1/partners#create" => "spec/requests/api/v1/partners_spec.rb, the partner is visible only to the current organization",
    "api/v1/partners#update" => "spec/requests/api/v1/partners_spec.rb, another organization's partner answers not_found and is unchanged",
    "api/v1/invitations#create" => "spec/requests/api/v1/invitations_spec.rb, the invitation is visible only to the current organization",
    "api/v1/invitations#index" => "spec/requests/api/v1/invitations_spec.rb, another organization's pending invitation never appears",
    "api/v1/invitations#destroy" => "spec/requests/api/v1/invitations_spec.rb, another organization's invitation answers not_found and is unchanged",
    "api/v1/memberships#index" => "spec/requests/api/v1/memberships_spec.rb, another organization's member never appears",
    "api/v1/memberships#update" => "spec/requests/api/v1/memberships_spec.rb, another organization's membership answers not_found and is unchanged",
    "api/v1/memberships#destroy" => "spec/requests/api/v1/memberships_spec.rb, another organization's membership answers not_found and is unchanged"
  }.freeze

  ROLE_MATRIX = {
    "api/v1/audit_events#index" => "spec/requests/api/v1/audit_events_spec.rb, one example per role",
    "api/v1/units#index" => "spec/requests/api/v1/units_spec.rb, one example per role",
    "api/v1/units#show" => "spec/requests/api/v1/units_spec.rb, one example per role",
    "api/v1/units#create" => "spec/requests/api/v1/units_spec.rb, one example per role",
    "api/v1/units#update" => "spec/requests/api/v1/units_spec.rb, one example per role",
    "api/v1/categories#index" => "spec/requests/api/v1/categories_spec.rb, one example per role",
    "api/v1/categories#show" => "spec/requests/api/v1/categories_spec.rb, one example per role",
    "api/v1/categories#create" => "spec/requests/api/v1/categories_spec.rb, one example per role",
    "api/v1/categories#update" => "spec/requests/api/v1/categories_spec.rb, one example per role",
    "api/v1/products#index" => "spec/requests/api/v1/products_spec.rb, one example per role",
    "api/v1/products#show" => "spec/requests/api/v1/products_spec.rb, one example per role",
    "api/v1/products#create" => "spec/requests/api/v1/products_spec.rb, one example per role",
    "api/v1/products#update" => "spec/requests/api/v1/products_spec.rb, one example per role",
    "api/v1/warehouses#index" => "spec/requests/api/v1/warehouses_spec.rb, one example per role",
    "api/v1/warehouses#show" => "spec/requests/api/v1/warehouses_spec.rb, one example per role",
    "api/v1/warehouses#create" => "spec/requests/api/v1/warehouses_spec.rb, one example per role",
    "api/v1/warehouses#update" => "spec/requests/api/v1/warehouses_spec.rb, one example per role",
    "api/v1/stock_balances#index" => "spec/requests/api/v1/stock_balances_spec.rb, one example per role",
    "api/v1/stock_movements#index" => "spec/requests/api/v1/stock_movements_spec.rb, one example per role",
    "api/v1/stock_adjustments#create" => "spec/requests/api/v1/stock_adjustments_spec.rb, one example per role",
    "api/v1/purchase_orders#index" => "spec/requests/api/v1/purchase_orders_spec.rb, one example per role",
    "api/v1/purchase_orders#show" => "spec/requests/api/v1/purchase_orders_spec.rb, read by every role but sales (index, and the CPF masking per role)",
    "api/v1/purchase_orders#create" => "spec/requests/api/v1/purchase_orders_spec.rb, one example per role",
    "api/v1/purchase_orders#update" => "spec/requests/api/v1/purchase_orders_spec.rb, one example per role",
    "api/v1/purchase_orders/approvals#create" => "spec/requests/api/v1/purchase_orders_spec.rb, one example per role",
    "api/v1/purchase_orders/cancellations#create" => "spec/requests/api/v1/purchase_orders_spec.rb, one example per role",
    "api/v1/purchase_orders/receipts#create" => "spec/requests/api/v1/receipts_spec.rb, one example per role",
    "api/v1/receipts#index" => "spec/requests/api/v1/receipts_spec.rb, one example per role",
    "api/v1/receipts#show" => "spec/requests/api/v1/receipts_spec.rb, read by every role but sales, the payable only for a role that reads payables",
    "api/v1/payables#index" => "spec/requests/api/v1/payables_spec.rb, one example per role",
    "api/v1/partners#index" => "spec/requests/api/v1/partners_spec.rb, one example per role",
    "api/v1/partners#show" => "spec/requests/api/v1/partners_spec.rb, one example per role",
    "api/v1/partners#create" => "spec/requests/api/v1/partners_spec.rb, one example per role",
    "api/v1/partners#update" => "spec/requests/api/v1/partners_spec.rb, one example per role",
    "api/v1/invitations#create" => "spec/requests/api/v1/invitations_spec.rb, one example per role",
    "api/v1/invitations#index" => "spec/requests/api/v1/invitations_spec.rb, one example per role",
    "api/v1/invitations#destroy" => "spec/requests/api/v1/invitations_spec.rb, one example per role",
    "api/v1/memberships#index" => "spec/requests/api/v1/memberships_spec.rb, one example per role",
    "api/v1/memberships#update" => "spec/requests/api/v1/memberships_spec.rb, one example per role",
    "api/v1/memberships#destroy" => "spec/requests/api/v1/memberships_spec.rb, one example per role"
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

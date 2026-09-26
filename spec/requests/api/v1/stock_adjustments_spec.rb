require "rails_helper"

RSpec.describe "Stock adjustments API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_membership(organization, role:)
    user = create(:user, password:)
    create(:membership, user:, organization:, role:)
    user
  end

  def sign_in_and_csrf(user)
    sign_in_via_api(email: user.email, password:)
    fetch_csrf_token
  end

  def headers(csrf_token, key: SecureRandom.uuid)
    { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => key }
  end

  def stock_setup(org = organization)
    set_current_tenant(org)
    [ create(:product, organization: org), create(:warehouse, organization: org) ]
  end

  def adjustment_params(product, warehouse, overrides = {})
    { product_id: product.id, warehouse_id: warehouse.id, counted_quantity: "10", reason: "opening_balance", unit_cost: "84.99" }.merge(overrides)
  end

  describe "POST /api/v1/stock_adjustments" do
    it "requires an existing session" do
      post "/api/v1/stock_adjustments", params: {}, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json,
        headers: { "Idempotency-Key" => SecureRandom.uuid }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "answers 400 without an Idempotency-Key, and 400 for a malformed one" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }
      expect(response).to have_http_status(:bad_request)
      assert_response_schema_confirm(400)
      expect(response.parsed_body.dig("error", "code")).to eq("idempotency_key_required")

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json,
        headers: headers(csrf_token, key: "short")
      expect(response).to have_http_status(:bad_request)
      set_current_tenant(organization)
      expect(Inventory::Movement.count).to eq(0)
    end

    # Role matrix (ADR 0008): owner, admin and purchasing adjust stock.
    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor = create_membership(organization, role:)
        product, warehouse = stock_setup
        csrf_token = sign_in_and_csrf(actor)

        post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token)

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        set_current_tenant(organization)
        expect(Inventory::Movement.count).to eq(expected_status == :created ? 1 : 0)
      end
    end

    it "writes the movement and returns it with the balance, in exact decimals and cents" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token)

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body.fetch("data")
      expect(data["movement"]).to include(
        "kind" => "adjustment", "reason" => "opening_balance", "quantity" => "10.000", "value_cents" => 850,
        "on_hand_after" => "10.000", "value_after_cents" => 850, "currency" => "BRL"
      )
      expect(data["movement"]["actor"]["id"]).to eq(owner.id)
      expect(data["balance"]).to include(
        "on_hand" => "10.000", "reserved" => "0.000", "available" => "10.000", "value_cents" => 850,
        "last_unit_cost" => "84.990000"
      )
    end

    it "replays a repeated request with the same key and creates nothing twice" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      request_headers = headers(csrf_token)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: request_headers
      first_id = response.parsed_body.dig("data", "movement", "id")
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: request_headers

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      expect(response.parsed_body.dig("data", "movement", "id")).to eq(first_id)
      set_current_tenant(organization)
      expect(Inventory::Movement.count).to eq(1)
    end

    it "answers 422 idempotency_key_reused for the same key with another body" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      request_headers = headers(csrf_token)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: request_headers
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, counted_quantity: "99"), as: :json,
        headers: request_headers

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("idempotency_key_reused")
      set_current_tenant(organization)
      expect(Inventory::Balance.sole.on_hand).to eq(BigDecimal("10"))
    end

    it "answers 200 with a null movement when the count matches the balance" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost: nil), as: :json, headers: headers(csrf_token)

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(response.parsed_body.dig("data", "movement")).to be_nil
      expect(response.parsed_body.dig("data", "balance", "on_hand")).to eq("10.000")
    end

    it "answers validation_failed with a kind per field and does not remember the attempt" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      key = SecureRandom.uuid

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost: nil), as: :json, headers: headers(csrf_token, key:)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("unit_cost" => [ "required" ])

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost: nil), as: :json, headers: headers(csrf_token, key:)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token, key:)
      expect(response).to have_http_status(:created)
    end

    it "answers 422 for a quantity with too many places or an unknown reason" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, counted_quantity: "1.2345", reason: "whim"), as: :json,
        headers: headers(csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq(
        "counted_quantity" => [ "too_many_decimals" ], "reason" => [ "inclusion" ]
      )
    end

    it "answers not_found for another organization's product or warehouse, writing nothing" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      foreign_product, foreign_warehouse = stock_setup(other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(foreign_product, warehouse), as: :json, headers: headers(csrf_token)
      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, foreign_warehouse), as: :json, headers: headers(csrf_token)
      expect(response).to have_http_status(:not_found)

      set_current_tenant(organization)
      expect(Inventory::Movement.count).to eq(0)
      expect(Inventory::Balance.count).to eq(0)
      set_current_tenant(other_organization)
      expect(Inventory::Movement.count).to eq(0)
    end

    it "keeps the adjustment visible only to the current organization" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token)

      set_current_tenant(other_organization)
      expect(Inventory::Movement.count).to eq(0)
      expect(Inventory::Balance.count).to eq(0)
      set_current_tenant(organization)
      expect(Inventory::Movement.count).to eq(1)
    end
  end
end

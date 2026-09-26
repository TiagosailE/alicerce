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
    { product_id: product.id, warehouse_id: warehouse.id, counted_quantity: "10", expected_on_hand: "0.000", reason: "opening_balance",
      unit_cost_cents: "84.99" }.merge(overrides)
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
        "last_unit_cost_cents" => "84.990000"
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

      post "/api/v1/stock_adjustments",
        params: adjustment_params(product, warehouse, expected_on_hand: "10.000", reason: "count", unit_cost_cents: nil),
        as: :json, headers: headers(csrf_token)

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

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost_cents: nil), as: :json, headers: headers(csrf_token, key:)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("unit_cost_cents" => [ "required" ])

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost_cents: nil), as: :json, headers: headers(csrf_token, key:)
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

    it "answers 409 stale with the current balance when the count is based on an old observation, writing nothing" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, counted_quantity: "5", expected_on_hand: "7.000", reason: "loss"),
        as: :json, headers: headers(csrf_token)

      expect(response).to have_http_status(:conflict)
      assert_response_schema_confirm(409)
      expect(response.parsed_body.dig("error", "code")).to eq("stale")
      expect(response.parsed_body.dig("error", "details", "current_on_hand")).to eq("10.000")
      set_current_tenant(organization)
      expect(Inventory::Movement.count).to eq(1)
    end

    it "answers validation_failed when expected_on_hand is missing" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse).except(:expected_on_hand), as: :json,
        headers: headers(csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to have_key("expected_on_hand")
    end

    it "treats a request that differs only in its query string as a different request (the key is not reused across them)" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      request_headers = headers(csrf_token)
      body = adjustment_params(product, warehouse).except(:counted_quantity)

      post "/api/v1/stock_adjustments?counted_quantity=11", params: body, as: :json, headers: request_headers
      expect(response).to have_http_status(:created)
      post "/api/v1/stock_adjustments?counted_quantity=99", params: body, as: :json, headers: request_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("idempotency_key_reused")
      set_current_tenant(organization)
      expect(Inventory::Balance.sole.on_hand).to eq(BigDecimal("11"))
    end

    it "refuses a note that is not a string, and a number that went through floating point" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, note: { a: "b" }), as: :json, headers: headers(csrf_token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("note" => [ "invalid" ])

      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, unit_cost_cents: 84.99999999999999999), as: :json,
        headers: headers(csrf_token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("unit_cost_cents" => [ "not_a_number" ])
    end

    it "answers 422, not 500, for a value that does not fit" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments",
        params: adjustment_params(product, warehouse, counted_quantity: "999999999999", unit_cost_cents: "9999999999999"), as: :json,
        headers: headers(csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("unit_cost_cents" => [ "too_large" ])
    end

    it "answers 422 for a product id that is not a single value" do
      owner = create_membership(organization, role: "owner")
      _product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/stock_adjustments", params: adjustment_params(Struct.new(:id).new([ 1, 2 ]), warehouse), as: :json, headers: headers(csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not let one user's key replay for another user" do
      owner = create_membership(organization, role: "owner")
      admin = create_membership(organization, role: "admin")
      product, warehouse = stock_setup
      key = SecureRandom.uuid
      csrf_token = sign_in_and_csrf(owner)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse), as: :json, headers: headers(csrf_token, key:)
      first_id = response.parsed_body.dig("data", "movement", "id")

      csrf_token = sign_in_and_csrf(admin)
      post "/api/v1/stock_adjustments", params: adjustment_params(product, warehouse, expected_on_hand: "10.000", counted_quantity: "12", reason: "found"),
        as: :json, headers: headers(csrf_token, key:)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("data", "movement", "id")).not_to eq(first_id)
    end

    it "answers 429 past the per-user ceiling, so a loop cannot fill the ledger" do
      owner = create_membership(organization, role: "owner")
      product, warehouse = stock_setup
      csrf_token = sign_in_and_csrf(owner)
      # Invalid on purpose: cheap, and each attempt still counts against the limit.
      bad = adjustment_params(product, warehouse, counted_quantity: "abc")

      statuses = 62.times.map do
        post "/api/v1/stock_adjustments", params: bad, as: :json, headers: headers(csrf_token)
        response.status
      end

      expect(statuses.first(60)).to all(eq(422))
      expect(statuses.last).to eq(429)
      assert_response_schema_confirm(429) if response.status == 429
    end

    it "answers 429 past the ceiling for the organization as a whole, however many accounts share it" do
      accounts = Array.new(4) { create_membership(organization, role: "owner") }
      product, warehouse = stock_setup
      bad = adjustment_params(product, warehouse, counted_quantity: "abc")
      statuses = []

      accounts.each do |account|
        csrf_token = sign_in_and_csrf(account)
        55.times do
          post "/api/v1/stock_adjustments", params: bad, as: :json, headers: headers(csrf_token)
          statuses << response.status
        end
      end

      # 4 x 55 = 220 requests: no account is over its own 60 a minute, the organization is over 200 in ten
      expect(statuses.first(200)).to all(eq(422))
      expect(statuses.last).to eq(429)
    end
  end
end

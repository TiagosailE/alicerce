require "rails_helper"

RSpec.describe "Receipts API" do
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

  def today(org = organization) = Time.current.in_time_zone(org.time_zone).to_date

  # An approved order of 200 bags at R$ 32,50 with 2% off, paid in two installments.
  def approved_cement_order(org = organization)
    set_current_tenant(org)
    supplier = supplier_for(org, name: "Cimentos Bahia")
    product = orderable_product(org, sku: "CIM-001", name: "Cimento CP II")
    order = approved_order!(organization: org, supplier:, actor: create(:user), installments: 2,
      lines: [ line_input(product, quantity: "200", unit_price_cents: 3_250, discount_bp: 200) ])
    line_ids[order.id] = order.lines.sole.id
    [ order, create(:warehouse, organization: org, name: "Deposito Central") ]
  end

  # Looked up when the order is built: once a request has run, the examples no
  # longer have a current tenant to read lines under.
  def line_ids = (@line_ids ||= {})

  def receipt_params(order, warehouse, quantity: "120", overrides: {})
    { warehouse_id: warehouse.id, received_on: today.to_s, supplier_invoice_number: "NF 1234",
      lines: [ { order_line_id: line_ids.fetch(order.id), quantity: } ] }.merge(overrides)
  end

  def post_receipt(order, params, csrf_token, key: SecureRandom.uuid)
    post "/api/v1/purchase_orders/#{order.id}/receipts", params:, as: :json, headers: headers(csrf_token, key:)
  end

  def posted_receipt(order, warehouse, quantity: "120")
    set_current_tenant(organization)
    Purchasing::ReceiveGoods.call(
      organization:, actor: create(:user), order:, warehouse:, lines: [ { order_line_id: order.lines.sole.id, quantity: } ],
      received_on: today.to_s, supplier_invoice_number: "NF 9", idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
    ).value
  end

  describe "POST /api/v1/purchase_orders/:id/receipts" do
    it "requires an existing session" do
      post "/api/v1/purchase_orders/1/receipts", params: {}, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token and an Idempotency-Key" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders/#{order.id}/receipts", params: receipt_params(order, warehouse), as: :json, headers: { "Idempotency-Key" => SecureRandom.uuid }
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")

      post "/api/v1/purchase_orders/#{order.id}/receipts", params: receipt_params(order, warehouse), as: :json, headers: { "X-CSRF-Token" => csrf_token }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("idempotency_key_required")
      assert_response_schema_confirm(400)
    end

    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden, "finance" => :forbidden,
      "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        order, warehouse = approved_cement_order
        csrf_token = sign_in_and_csrf(user)

        post_receipt(order, receipt_params(order, warehouse), csrf_token)

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        set_current_tenant(organization)
        expect(Purchasing::Receipt.count).to eq(expected_status == :created ? 1 : 0)
      end
    end

    it "receives the goods: the receipt as a report, stock in at the net cost, the payable opened, the order partially received" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)

      post_receipt(order, receipt_params(order, warehouse), csrf_token)

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body["data"]
      expect(data).to include("number" => 1, "status" => "posted", "total_cents" => 382_200, "currency" => "BRL", "received_on" => today.to_s,
        "supplier_invoice_number" => "NF 1234", "order" => { "id" => order.id, "number" => order.number },
        "supplier" => include("name" => "Cimentos Bahia"), "warehouse" => { "id" => warehouse.id, "name" => "Deposito Central" },
        "created_by" => { "id" => owner.id, "name" => owner.name })
      expect(data["lines"].sole).to include(
        "order_line_id" => line_ids.fetch(order.id), "purchase_unit_code" => "SC", "stock_unit_code" => "UN", "factor" => "1.000000",
        "unit_price_cents" => 3_250, "discount_bp" => 200, "quantity" => "120.000", "stock_quantity" => "120.000",
        "gross_cents" => 390_000, "discount_cents" => 7_800, "net_cents" => 382_200
      )
      expect(data["payable"]).to include("kind" => "payable", "status" => "open", "total_cents" => 382_200, "settled_cents" => 0, "open_cents" => 382_200,
        "partner" => include("name" => "Cimentos Bahia"), "receipt" => { "id" => data["id"], "number" => 1 })
      expect(data["payable"]["installments"].map { |i| [ i["number"], i["due_on"], i["amount_cents"] ] })
        .to eq([ [ 1, (today + 30).to_s, 191_100 ], [ 2, (today + 60).to_s, 191_100 ] ])
      set_current_tenant(organization)
      expect(order.reload.status).to eq("partially_received")
    end

    it "leaves the payable out for a role that does not read payables, and still receives" do
      purchasing = create_membership(organization, role: "purchasing")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(purchasing)

      post_receipt(order, receipt_params(order, warehouse), csrf_token)

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      expect(response.parsed_body.dig("data", "payable")).to be_nil
      set_current_tenant(organization)
      expect(Finance::Title.count).to eq(1)
      expect(response.body).not_to include("installments")
    end

    it "answers the same 201 and the same receipt for the same key and request, writing nothing twice" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)
      params = receipt_params(order, warehouse)

      post_receipt(order, params, csrf_token, key: "receive-key-1")
      first = response.parsed_body.dig("data", "id")
      post_receipt(order, params, csrf_token, key: "receive-key-1")

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      expect(response.parsed_body.dig("data", "id")).to eq(first)
      set_current_tenant(organization)
      expect([ Purchasing::Receipt.count, Inventory::Movement.count, Finance::Title.count ]).to eq([ 1, 1, 1 ])

      post_receipt(order, receipt_params(order, warehouse, quantity: "50"), csrf_token, key: "receive-key-1")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("idempotency_key_reused")
      assert_response_schema_confirm(422)
    end

    it "answers not_found for another organization's order, warehouse, and writes nothing" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      foreign_order, foreign_warehouse = approved_cement_order(other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post_receipt(foreign_order, receipt_params(foreign_order, warehouse), csrf_token)
      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)

      post_receipt(order, receipt_params(order, foreign_warehouse), csrf_token)
      expect(response).to have_http_status(:not_found)

      set_current_tenant(organization)
      expect(Purchasing::Receipt.count).to eq(0)
      set_current_tenant(other_organization)
      expect(Purchasing::Receipt.count).to eq(0)
      expect(foreign_order.reload.status).to eq("approved")
    end

    it "answers validation_failed for another organization's order line, as an order line that is not this order's" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      foreign_order, = approved_cement_order(other_organization)
      csrf_token = sign_in_and_csrf(owner)
      params = receipt_params(order, warehouse, overrides: { lines: [ { order_line_id: line_ids.fetch(foreign_order.id), quantity: "1" } ] })

      post_receipt(order, params, csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("lines.0.order_line_id" => [ "not_found" ])
    end

    it "answers 422 over_receipt, and 409 invalid_transition for an order that is not approved" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)

      post_receipt(order, receipt_params(order, warehouse, quantity: "200.001"), csrf_token)
      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("lines.0.quantity" => [ "over_receipt" ])

      post "/api/v1/purchase_orders/#{order.id}/cancellation", headers: { "X-CSRF-Token" => csrf_token }
      post_receipt(order, receipt_params(order, warehouse), csrf_token)
      expect(response).to have_http_status(:conflict)
      assert_response_schema_confirm(409)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_transition")
    end

    it "answers validation_failed with a kind per field, never a 500" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)

      post_receipt(order, receipt_params(order, warehouse, overrides: {
        received_on: (today + 1).to_s, supplier_invoice_number: "x" * 61, lines: [ { order_line_id: line_ids.fetch(order.id), quantity: "1.5555" } ]
      }), csrf_token)

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq(
        "lines.0.quantity" => [ "too_many_decimals" ], "received_on" => [ "in_the_future" ], "supplier_invoice_number" => [ "too_long" ]
      )
    end

    it "answers validation_failed for lines that are not a list, a date that is not text and a missing warehouse" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)

      post_receipt(order, receipt_params(order, warehouse, overrides: { lines: { order_line_id: 1 } }), csrf_token)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("lines" => [ "blank" ])

      post_receipt(order, receipt_params(order, warehouse, overrides: { received_on: [ "2026-01-01" ] }), csrf_token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("received_on" => [ "invalid" ])

      post_receipt(order, receipt_params(order, warehouse).except(:warehouse_id), csrf_token)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("warehouse_id" => [ "blank" ])
      set_current_tenant(organization)
      expect(Purchasing::Receipt.count).to eq(0)
    end

    it "answers 429 past the per-user ceiling on writes" do
      owner = create_membership(organization, role: "owner")
      order, warehouse = approved_cement_order
      csrf_token = sign_in_and_csrf(owner)
      bad = receipt_params(order, warehouse, overrides: { lines: [] })

      statuses = 62.times.map do
        post_receipt(order, bad, csrf_token)
        response.status
      end

      expect(statuses.first(60)).to all(eq(422))
      expect(statuses.last).to eq(429)
    end
  end

  describe "GET /api/v1/receipts" do
    it "requires an existing session" do
      get "/api/v1/receipts"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "finance" => :ok, "read_only" => :ok, "sales" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/receipts"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's receipts, newest number first, and filters them" do
      user = create_membership(organization, role: "finance")
      order, warehouse = approved_cement_order
      first = posted_receipt(order, warehouse, quantity: "10")
      second = posted_receipt(order, warehouse, quantity: "20")
      other_order, other_warehouse = approved_cement_order(other_organization)
      set_current_tenant(other_organization)
      Purchasing::ReceiveGoods.call(
        organization: other_organization, actor: create(:user), order: other_order, warehouse: other_warehouse, received_on: today(other_organization).to_s,
        lines: [ { order_line_id: other_order.lines.sole.id, quantity: "5" } ], idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
      )
      set_current_tenant(organization)
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/receipts"
      assert_response_schema_confirm(200)
      expect(response.parsed_body["data"].map { |row| row["number"] }).to eq([ second.number, first.number ])
      expect(response.parsed_body["data"].first).to include("order" => { "id" => order.id, "number" => order.number }, "warehouse" => include("name" => "Deposito Central"))
      expect(response.parsed_body["meta"]["total"]).to eq(2)

      get "/api/v1/receipts", params: { q: "bahia" }
      expect(response.parsed_body["meta"]["total"]).to eq(2)
      get "/api/v1/receipts", params: { q: first.number.to_s }
      expect(response.parsed_body["data"].map { |row| row["id"] }).to eq([ first.id ])
      get "/api/v1/receipts", params: { order_id: order.id, warehouse_id: warehouse.id }
      expect(response.parsed_body["meta"]["total"]).to eq(2)
      get "/api/v1/receipts", params: { order_id: 0 }
      expect(response.parsed_body["meta"]["total"]).to eq(0)
    end
  end

  describe "GET /api/v1/receipts/:id" do
    it "answers not_found for another organization's receipt" do
      user = create_membership(organization, role: "owner")
      other_order, other_warehouse = approved_cement_order(other_organization)
      set_current_tenant(other_organization)
      foreign = Purchasing::ReceiveGoods.call(
        organization: other_organization, actor: create(:user), order: other_order, warehouse: other_warehouse, received_on: today(other_organization).to_s,
        lines: [ { order_line_id: other_order.lines.sole.id, quantity: "5" } ], idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
      ).value
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/receipts/#{foreign.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    it "shows the report, with the payable to a role that reads payables and without it to purchasing" do
      order, warehouse = approved_cement_order
      receipt = posted_receipt(order, warehouse)
      finance = create_membership(organization, role: "finance")
      purchasing = create_membership(organization, role: "purchasing")
      sales = create_membership(organization, role: "sales")

      sign_in_via_api(email: finance.email, password:)
      get "/api/v1/receipts/#{receipt.id}"
      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(response.parsed_body.dig("data", "payable", "total_cents")).to eq(382_200)
      expect(response.parsed_body.dig("data", "lines", 0, "net_cents")).to eq(382_200)

      sign_in_via_api(email: purchasing.email, password:)
      get "/api/v1/receipts/#{receipt.id}"
      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(response.parsed_body.dig("data", "payable")).to be_nil

      sign_in_via_api(email: sales.email, password:)
      get "/api/v1/receipts/#{receipt.id}"
      expect(response).to have_http_status(:forbidden)
    end
  end
end

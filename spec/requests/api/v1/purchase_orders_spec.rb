require "rails_helper"

RSpec.describe "Purchase orders API" do
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

  def setup_supplier_and_product(org = organization)
    set_current_tenant(org)
    supplier = Catalog::Partner.find_by(name: "Cimentos Bahia") || supplier_for(org, name: "Cimentos Bahia")
    product = Catalog::Product.find_by(sku: "CIM-001") || orderable_product(org, sku: "CIM-001", name: "Cimento CP II")
    [ supplier, product ]
  end

  def order_params(supplier, product, overrides = {})
    { supplier_id: supplier.id, installments: 2, first_due_days: 30, interval_days: 30, note: "Entrega na segunda",
      lines: [ { product_id: product.id, quantity: "200", unit_price_cents: 3_250, discount_bp: 200 } ] }.merge(overrides)
  end

  def existing_order(org = organization, actor: create(:user))
    supplier, product = setup_supplier_and_product(org)
    create_order!(organization: org, supplier:, actor:, lines: [ line_input(product, quantity: "200", unit_price_cents: 3_250, discount_bp: 200) ])
  end

  describe "GET /api/v1/purchase_orders" do
    it "requires an existing session" do
      get "/api/v1/purchase_orders"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # ADR 0008: sales has no access to purchasing; everyone else reads.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "finance" => :ok, "read_only" => :ok, "sales" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/purchase_orders"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's orders, newest number first, and filters them" do
      user = create_membership(organization, role: "finance")
      first = existing_order
      second = existing_order
      Purchasing::CancelOrder.call(order: first, actor: user)
      existing_order(other_organization)
      set_current_tenant(organization)
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/purchase_orders"
      assert_response_schema_confirm(200)
      expect(response.parsed_body["data"].map { |row| row["number"] }).to eq([ second.number, first.number ])
      expect(response.parsed_body["data"].first).to include("status" => "draft", "total_cents" => 637_000, "currency" => "BRL")
      expect(response.parsed_body["meta"]["total"]).to eq(2)

      get "/api/v1/purchase_orders", params: { status: "cancelled" }
      expect(response.parsed_body["data"].map { |row| row["id"] }).to eq([ first.id ])

      get "/api/v1/purchase_orders", params: { q: "bahia" }
      expect(response.parsed_body["meta"]["total"]).to eq(2)
      get "/api/v1/purchase_orders", params: { q: second.number.to_s }
      expect(response.parsed_body["data"].map { |row| row["id"] }).to eq([ second.id ])
    end
  end

  describe "GET /api/v1/purchase_orders/:id" do
    it "answers not_found for another organization's order" do
      user = create_membership(organization, role: "owner")
      foreign = existing_order(other_organization)
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/purchase_orders/#{foreign.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    it "returns the order with its lines, exact amounts and quantities" do
      user = create_membership(organization, role: "purchasing")
      order = existing_order
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/purchase_orders/#{order.id}"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      data = response.parsed_body["data"]
      expect(data).to include("number" => order.number, "status" => "draft", "revision" => 0, "total_cents" => 637_000)
      expect(data["lines"].sole).to include(
        "position" => 1, "purchase_unit_code" => "SC", "factor" => "1.000000", "quantity" => "200.000",
        "received_quantity" => "0.000", "remaining_quantity" => "200.000", "unit_price_cents" => 3_250,
        "discount_bp" => 200, "gross_cents" => 650_000, "discount_cents" => 13_000, "net_cents" => 637_000
      )
    end

    it "shows the supplier's CPF in full to a role that may see partners' and masked to read_only" do
      set_current_tenant(organization)
      cpf = DocumentNumberGenerator.cpf
      supplier = supplier_for(organization, document_type: "cpf", document_number: cpf, name: "Marcos Pereira")
      product = orderable_product(organization, sku: "CIM-001")
      order = create_order!(organization:, supplier:, actor: create(:user), lines: [ line_input(product) ])
      finance = create_membership(organization, role: "finance")
      read_only = create_membership(organization, role: "read_only")

      sign_in_via_api(email: finance.email, password:)
      get "/api/v1/purchase_orders/#{order.id}"
      expect(response.parsed_body.dig("data", "supplier", "document_number")).to eq(cpf)
      expect(response.parsed_body.dig("data", "personal_data_visible")).to be(true)

      sign_in_via_api(email: read_only.email, password:)
      get "/api/v1/purchase_orders/#{order.id}"
      assert_response_schema_confirm(200)
      expect(response.parsed_body.dig("data", "supplier", "document_number")).to eq("***#{cpf[3, 6]}**")
      expect(response.parsed_body.dig("data", "personal_data_visible")).to be(false)
      expect(response.body).not_to include(cpf)
    end
  end

  describe "POST /api/v1/purchase_orders" do
    it "requires the CSRF token" do
      owner = create_membership(organization, role: "owner")
      supplier, product = setup_supplier_and_product
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/purchase_orders", params: order_params(supplier, product), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden, "finance" => :forbidden,
      "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        supplier, product = setup_supplier_and_product
        csrf_token = sign_in_and_csrf(user)

        post "/api/v1/purchase_orders", params: order_params(supplier, product), as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        set_current_tenant(organization)
        expect(Purchasing::Order.count).to eq(expected_status == :created ? 1 : 0)
      end
    end

    it "creates a numbered draft with the amounts worked out, visible only to the current organization" do
      owner = create_membership(organization, role: "owner")
      supplier, product = setup_supplier_and_product
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders", params: order_params(supplier, product), as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      expect(response.parsed_body["data"]).to include("number" => 1, "status" => "draft", "total_cents" => 637_000, "installments" => 2, "note" => "Entrega na segunda")
      set_current_tenant(other_organization)
      expect(Purchasing::Order.count).to eq(0)
    end

    it "answers not_found for another organization's supplier, writing nothing" do
      owner = create_membership(organization, role: "owner")
      _supplier, product = setup_supplier_and_product
      foreign_supplier, = setup_supplier_and_product(other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders", params: order_params(foreign_supplier, product), as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      set_current_tenant(organization)
      expect(Purchasing::Order.count).to eq(0)
    end

    it "answers validation_failed with a kind per field, never a 500" do
      owner = create_membership(organization, role: "owner")
      supplier, product = setup_supplier_and_product
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders",
        params: order_params(supplier, product, lines: [ { product_id: product.id, quantity: "1.2345", unit_price_cents: 10.5 } ]),
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq(
        "lines.0.quantity" => [ "too_many_decimals" ], "lines.0.unit_price_cents" => [ "not_a_number" ]
      )
    end

    it "answers validation_failed when the lines are not a list" do
      owner = create_membership(organization, role: "owner")
      supplier, product = setup_supplier_and_product
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders", params: order_params(supplier, product, lines: { product_id: product.id }), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to eq("lines" => [ "blank" ])
    end
  end

  describe "PATCH /api/v1/purchase_orders/:id" do
    it "updates a draft, answers 409 stale for an older revision and 409 invalid_transition once approved" do
      owner = create_membership(organization, role: "owner")
      order = existing_order
      supplier = order.supplier
      product = order.lines.first.product
      csrf_token = sign_in_and_csrf(owner)
      headers = { "X-CSRF-Token" => csrf_token }
      params = order_params(supplier, product, revision: 0, note: "Editado", lines: [ { product_id: product.id, quantity: "10", unit_price_cents: 100 } ])

      patch("/api/v1/purchase_orders/#{order.id}", params:, as: :json, headers:)
      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(response.parsed_body["data"]).to include("revision" => 1, "note" => "Editado", "total_cents" => 1_000)

      patch("/api/v1/purchase_orders/#{order.id}", params: params.merge(note: "Antigo"), as: :json, headers:)
      expect(response).to have_http_status(:conflict)
      assert_response_schema_confirm(409)
      expect(response.parsed_body.dig("error", "code")).to eq("stale")

      post "/api/v1/purchase_orders/#{order.id}/approval", params: { revision: 1 }, as: :json, headers: headers
      patch("/api/v1/purchase_orders/#{order.id}", params: params.merge(revision: 2), as: :json, headers:)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_transition")
    end

    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden, "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        order = existing_order
        csrf_token = sign_in_and_csrf(user)

        patch "/api/v1/purchase_orders/#{order.id}",
          params: order_params(order.supplier, order.lines.first.product, revision: 0), as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "answers not_found for another organization's order, leaving it unchanged" do
      owner = create_membership(organization, role: "owner")
      foreign = existing_order(other_organization)
      supplier, product = setup_supplier_and_product
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/purchase_orders/#{foreign.id}", params: order_params(supplier, product, revision: 0), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      set_current_tenant(other_organization)
      expect(foreign.reload.revision).to eq(0)
    end
  end

  describe "POST /api/v1/purchase_orders/:id/approval" do
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden, "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        order = existing_order
        csrf_token = sign_in_and_csrf(user)

        post "/api/v1/purchase_orders/#{order.id}/approval", params: { revision: 0 }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "approves with the revision that was read, refuses an older one and a missing one, and cannot approve twice" do
      owner = create_membership(organization, role: "owner")
      order = existing_order
      csrf_token = sign_in_and_csrf(owner)
      headers = { "X-CSRF-Token" => csrf_token }

      post "/api/v1/purchase_orders/#{order.id}/approval", params: {}, as: :json, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "fields")).to have_key("revision")

      post "/api/v1/purchase_orders/#{order.id}/approval", params: { revision: 7 }, as: :json, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig("error", "code")).to eq("stale")

      post "/api/v1/purchase_orders/#{order.id}/approval", params: { revision: 0 }, as: :json, headers: headers
      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(response.parsed_body["data"]).to include("status" => "approved", "revision" => 1)
      expect(response.parsed_body["data"]["approved_at"]).not_to be_nil

      post "/api/v1/purchase_orders/#{order.id}/approval", params: { revision: 1 }, as: :json, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_transition")
    end

    it "answers not_found for another organization's order" do
      owner = create_membership(organization, role: "owner")
      foreign = existing_order(other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders/#{foreign.id}/approval", params: { revision: 0 }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      set_current_tenant(other_organization)
      expect(foreign.reload.status).to eq("draft")
    end
  end

  describe "POST /api/v1/purchase_orders/:id/cancellation" do
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden, "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        order = existing_order
        csrf_token = sign_in_and_csrf(user)

        post "/api/v1/purchase_orders/#{order.id}/cancellation", as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "cancels once and answers 409 invalid_transition after" do
      owner = create_membership(organization, role: "owner")
      order = existing_order
      csrf_token = sign_in_and_csrf(owner)
      headers = { "X-CSRF-Token" => csrf_token }

      post "/api/v1/purchase_orders/#{order.id}/cancellation", as: :json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("status" => "cancelled")

      post "/api/v1/purchase_orders/#{order.id}/cancellation", as: :json, headers: headers
      expect(response).to have_http_status(:conflict)
      assert_response_schema_confirm(409)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_transition")
    end

    it "answers not_found for another organization's order" do
      owner = create_membership(organization, role: "owner")
      foreign = existing_order(other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/purchase_orders/#{foreign.id}/cancellation", as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      set_current_tenant(other_organization)
      expect(foreign.reload.status).to eq("draft")
    end
  end
end

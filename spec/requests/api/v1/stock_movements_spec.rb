require "rails_helper"

RSpec.describe "Stock movements API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:actor) { create(:user, name: "Joana Lima") }

  def create_membership(organization, role:)
    user = create(:user, password:)
    create(:membership, user:, organization:, role:)
    user
  end

  # expected defaults to the balance as it stands, like a client that just looked.
  def adjust!(org, product, warehouse, quantity, reason: "count", cost: nil)
    set_current_tenant(org)
    current = Inventory::Balance.find_by(product_id: product.id, warehouse_id: warehouse.id)
    expected = current ? current.on_hand.to_s("F") : "0"
    result = Inventory::AdjustStock.call(
      organization: org, actor:, product:, warehouse:, counted_quantity: quantity, expected_on_hand: expected, reason:,
      unit_cost_cents: cost, idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(8)
    )
    raise result.error.to_s unless result.success?
  end

  describe "GET /api/v1/stock_movements" do
    it "requires an existing session" do
      get "/api/v1/stock_movements"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # ADR 0016: the ledger names who moved what and carries free text, so sales
    # (who reads balances, quantities only) does not read it.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden, "finance" => :ok,
      "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/stock_movements"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists the ledger newest first, with who did it and the balance after, and never another organization's" do
      user = create_membership(organization, role: "finance")
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:)
      product = create(:product, organization:)
      adjust!(organization, product, warehouse, "10", reason: "opening_balance", cost: "84.99")
      adjust!(organization, product, warehouse, "7", reason: "loss")
      set_current_tenant(other_organization)
      adjust!(other_organization, create(:product, organization: other_organization), create(:warehouse, organization: other_organization),
        "5", reason: "opening_balance", cost: "1")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_movements"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      rows = response.parsed_body["data"]
      expect(rows.map { |row| row["reason"] }).to eq(%w[loss opening_balance])
      expect(rows.first).to include("quantity" => "-3.000", "value_cents" => -255, "on_hand_after" => "7.000", "value_after_cents" => 595)
      expect(rows.first["actor"]).to eq("id" => actor.id, "name" => "Joana Lima")
      expect(response.parsed_body["meta"]["total"]).to eq(2)
    end

    it "points a receipt movement at its receipt, and leaves the link null for a count" do
      user = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:)
      product = orderable_product(organization, sku: "CIM-001")
      order = approved_order!(organization:, supplier: supplier_for(organization), actor:, lines: [ line_input(product, quantity: "10", unit_price_cents: 1_000) ])
      receipt = Purchasing::ReceiveGoods.call(
        organization:, actor:, order:, warehouse:, lines: [ { order_line_id: order.lines.sole.id, quantity: "4" } ],
        received_on: Time.current.in_time_zone(organization.time_zone).to_date.to_s, idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
      ).value
      adjust!(organization, product, warehouse, "3", reason: "loss")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_movements"

      assert_response_schema_confirm(200)
      rows = response.parsed_body["data"]
      expect(rows.map { |row| row["kind"] }).to eq(%w[adjustment receipt])
      expect(rows.first["receipt"]).to be_nil
      expect(rows.last).to include("reason" => nil, "quantity" => "4.000", "value_cents" => 4_000, "receipt" => { "id" => receipt.id, "number" => receipt.number })
    end

    it "filters by product, warehouse and reason" do
      user = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      loja = create(:warehouse, organization:, name: "Loja")
      patio = create(:warehouse, organization:, name: "Patio")
      product = create(:product, organization:)
      adjust!(organization, product, loja, "10", reason: "opening_balance", cost: "10")
      adjust!(organization, product, patio, "4", reason: "opening_balance", cost: "10")
      adjust!(organization, product, loja, "8", reason: "damage")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_movements", params: { warehouse_id: patio.id }
      expect(response.parsed_body["meta"]["total"]).to eq(1)

      get "/api/v1/stock_movements", params: { reason: "damage" }
      expect(response.parsed_body["data"].map { |row| row["quantity"] }).to eq([ "-2.000" ])

      get "/api/v1/stock_movements", params: { product_id: product.id }
      expect(response.parsed_body["meta"]["total"]).to eq(3)
    end

    it "shows finance the values and the note, and never lets sales see any of it" do
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:)
      product = create(:product, organization:)
      adjust!(organization, product, warehouse, "10", reason: "opening_balance", cost: "84.99")
      sales = create_membership(organization, role: "sales")
      finance = create_membership(organization, role: "finance")

      sign_in_via_api(email: finance.email, password:)
      get "/api/v1/stock_movements"
      expect(response.parsed_body["data"].first).to include("value_cents" => 850, "value_after_cents" => 850)

      sign_in_via_api(email: sales.email, password:)
      get "/api/v1/stock_movements"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("850")
    end

    it "orders the ledger by id, newest first, whatever the clock said" do
      user = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:)
      product = create(:product, organization:)
      adjust!(organization, product, warehouse, "10", reason: "opening_balance", cost: "10")
      adjust!(organization, product, warehouse, "8", reason: "loss")
      adjust!(organization, product, warehouse, "9", reason: "found")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_movements"

      ids = response.parsed_body["data"].map { |row| row["id"] }
      expect(ids).to eq(ids.sort.reverse)
    end
  end
end

require "rails_helper"

RSpec.describe "Stock balances API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:actor) { create(:user) }

  def create_membership(organization, role:)
    user = create(:user, password:)
    create(:membership, user:, organization:, role:)
    user
  end

  def stock!(org, product, warehouse, quantity, cost: "10")
    set_current_tenant(org)
    result = Inventory::AdjustStock.call(
      organization: org, actor:, product:, warehouse:, counted_quantity: quantity, expected_on_hand: "0", reason: "opening_balance",
      unit_cost_cents: cost, idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(8)
    )
    raise result.error.to_s unless result.success?
  end

  describe "GET /api/v1/stock_balances" do
    it "requires an existing session" do
      get "/api/v1/stock_balances"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # ADR 0016: every role can read the stock position.
    %w[owner admin purchasing sales finance read_only].each do |role|
      it "answers ok for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/stock_balances"

        expect(response).to have_http_status(:ok)
        assert_response_schema_confirm(200)
      end
    end

    it "lists only the current organization's balances, by product name, with available stock and value" do
      user = create_membership(organization, role: "finance")
      set_current_tenant(organization)
      loja = create(:warehouse, organization:, name: "Loja")
      cimento = create(:product, organization:, sku: "CIM-50", name: "Cimento 50kg")
      areia = create(:product, organization:, sku: "ARE-01", name: "Areia media")
      stock!(organization, cimento, loja, "120.500", cost: "3250")
      stock!(organization, areia, loja, "8")
      set_current_tenant(other_organization)
      other_warehouse = create(:warehouse, organization: other_organization)
      other_product = create(:product, organization: other_organization, name: "Produto alheio")
      stock!(other_organization, other_product, other_warehouse, "5")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_balances"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      rows = response.parsed_body["data"]
      expect(rows.map { |row| row.dig("product", "name") }).to eq([ "Areia media", "Cimento 50kg" ])
      expect(rows.last).to include("on_hand" => "120.500", "reserved" => "0.000", "available" => "120.500", "value_cents" => 391_625)
      expect(rows.last["warehouse"]["name"]).to eq("Loja")
      expect(response.parsed_body["meta"]).to eq("page" => 1, "per_page" => 25, "total" => 2)
    end

    it "filters by warehouse and by product name or sku" do
      user = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      loja = create(:warehouse, organization:, name: "Loja")
      patio = create(:warehouse, organization:, name: "Patio")
      cimento = create(:product, organization:, sku: "CIM-50", name: "Cimento 50kg")
      areia = create(:product, organization:, sku: "ARE-01", name: "Areia media")
      stock!(organization, cimento, loja, "1")
      stock!(organization, cimento, patio, "2")
      stock!(organization, areia, loja, "3")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_balances", params: { warehouse_id: patio.id }
      expect(response.parsed_body["data"].map { |row| row["on_hand"] }).to eq([ "2.000" ])

      get "/api/v1/stock_balances", params: { q: "cim-5" }
      expect(response.parsed_body["data"].map { |row| row["on_hand"] }).to eq([ "1.000", "2.000" ])

      get "/api/v1/stock_balances", params: { product_id: areia.id }
      expect(response.parsed_body["meta"]["total"]).to eq(1)
    end

    # ADR 0016: what stock is worth and cost is margin data. Every role reads
    # quantities; only sales does not read values.
    %w[owner admin purchasing finance read_only].each do |role|
      it "shows the #{role} role the value and the last cost" do
        user = create_membership(organization, role:)
        set_current_tenant(organization)
        stock!(organization, create(:product, organization:), create(:warehouse, organization:), "10", cost: "84.99")
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/stock_balances"

        assert_response_schema_confirm(200)
        expect(response.parsed_body["data"].first).to include("value_cents" => 850, "last_unit_cost_cents" => "84.990000")
      end
    end

    it "hides the value and the last cost from the sales role, who still sees quantities" do
      user = create_membership(organization, role: "sales")
      set_current_tenant(organization)
      stock!(organization, create(:product, organization:), create(:warehouse, organization:), "10", cost: "84.99")
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/stock_balances"

      assert_response_schema_confirm(200)
      row = response.parsed_body["data"].first
      expect(row).to include("on_hand" => "10.000", "available" => "10.000", "value_cents" => nil, "last_unit_cost_cents" => nil)
      expect(response.body).not_to include("84.99")
    end
  end
end

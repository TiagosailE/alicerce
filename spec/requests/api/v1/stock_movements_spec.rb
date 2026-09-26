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

  def adjust!(org, product, warehouse, quantity, reason: "count", cost: nil)
    set_current_tenant(org)
    result = Inventory::AdjustStock.call(
      organization: org, actor:, product:, warehouse:, counted_quantity: quantity, reason:, unit_cost: cost,
      idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(8)
    )
    raise result.error.to_s unless result.success?
  end

  describe "GET /api/v1/stock_movements" do
    it "requires an existing session" do
      get "/api/v1/stock_movements"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    %w[owner admin purchasing sales finance read_only].each do |role|
      it "answers ok for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/stock_movements"

        expect(response).to have_http_status(:ok)
        assert_response_schema_confirm(200)
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
  end
end

require "rails_helper"

RSpec.describe "Payables API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_membership(organization, role:)
    user = create(:user, password:)
    create(:membership, user:, organization:, role:)
    user
  end

  def receive_into(org, supplier_name:, quantity: "10", installments: 2)
    set_current_tenant(org)
    supplier = supplier_for(org, name: supplier_name)
    product = orderable_product(org, sku: "SKU-#{SecureRandom.hex(3)}", name: "Produto")
    order = approved_order!(organization: org, supplier:, actor: create(:user), installments:,
      lines: [ line_input(product, quantity:, unit_price_cents: 3_250) ])
    Purchasing::ReceiveGoods.call(
      organization: org, actor: create(:user), order:, warehouse: create(:warehouse, organization: org),
      lines: [ { order_line_id: order.lines.sole.id, quantity: } ], received_on: Time.current.in_time_zone(org.time_zone).to_date.to_s,
      idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
    ).value
  end

  describe "GET /api/v1/payables" do
    it "requires an existing session" do
      get "/api/v1/payables"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    { "owner" => :ok, "admin" => :ok, "finance" => :ok, "read_only" => :ok, "purchasing" => :forbidden, "sales" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/payables"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's payables, newest first, with their installments and exact amounts, and filters them" do
      user = create_membership(organization, role: "finance")
      older = receive_into(organization, supplier_name: "Cimentos Bahia", quantity: "10", installments: 2)
      newer = receive_into(organization, supplier_name: "Tintas Rio", quantity: "1", installments: 3)
      receive_into(other_organization, supplier_name: "Cimentos Bahia")
      set_current_tenant(organization)
      sign_in_via_api(email: user.email, password:)

      get "/api/v1/payables"

      assert_response_schema_confirm(200)
      rows = response.parsed_body["data"]
      expect(rows.map { |row| row["id"] }).to eq([ newer.title.id, older.title.id ])
      expect(rows.first).to include("kind" => "payable", "status" => "open", "total_cents" => 3_250, "receipt" => { "id" => newer.id, "number" => newer.number })
      expect(rows.first["installments"].map { |i| i["amount_cents"] }).to eq([ 1_084, 1_083, 1_083 ])
      expect(rows.first["installments"].sum { |i| i["amount_cents"] }).to eq(rows.first["total_cents"])
      expect(response.parsed_body["meta"]["total"]).to eq(2)

      get "/api/v1/payables", params: { q: "tintas" }
      expect(response.parsed_body["data"].map { |row| row["id"] }).to eq([ newer.title.id ])
      get "/api/v1/payables", params: { status: "cancelled" }
      expect(response.parsed_body["meta"]["total"]).to eq(0)
    end
  end
end

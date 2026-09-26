require "rails_helper"

RSpec.describe Inventory::MovementSerializer do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:product) { orderable_product(organization, sku: "CIM-001") }
  let(:movement) do
    order = approved_order!(organization:, supplier: supplier_for(organization), actor:, lines: [ line_input(product, quantity: "10", unit_price_cents: 1_000) ])
    Purchasing::ReceiveGoods.call(
      organization:, actor:, order:, warehouse:, lines: [ { order_line_id: order.lines.sole.id, quantity: "4" } ],
      received_on: Time.current.in_time_zone(organization.time_zone).to_date.to_s, idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
    ).value.lines.sole.movement
  end

  before { set_current_tenant(organization) }

  it "points a receipt movement at its receipt only for a reader who may see purchasing" do
    expect(described_class.new(movement, receipt_visible: true).as_json[:receipt]).to eq(id: movement.receipt_line.receipt_id, number: 1)
    expect(described_class.new(movement, receipt_visible: false).as_json[:receipt]).to be_nil
    expect(described_class.new(movement).as_json[:receipt]).to be_nil
  end
end

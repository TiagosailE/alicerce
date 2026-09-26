require "rails_helper"

RSpec.describe Purchasing::UpdateOrder do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization) }
  let(:cimento) { orderable_product(organization, sku: "CIM-001") }
  let(:areia) { orderable_product(organization, sku: "ARE-001", purchase_unit_code: "M3") }
  let(:order) { create_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "10", unit_price_cents: 3_250) ]) }

  before { set_current_tenant(organization) }

  def update(order = self.order, revision: order.revision, supplier: self.supplier, lines: [ line_input(cimento) ], **terms)
    described_class.call(order:, actor:, revision:, supplier:, lines:, installments: 1, first_due_days: 30, interval_days: 30, **terms)
  end

  it "replaces the lines, works out the total again and bumps the revision" do
    result = update(lines: [ line_input(areia, quantity: "2.5", unit_price_cents: 8_990, discount_bp: 1_000) ], installments: 2, note: "Novo")

    expect(result).to be_success
    order.reload
    expect(order).to have_attributes(revision: 1, total_cents: 20_227, installments: 2, note: "Novo")
    expect(order.lines.map(&:product_sku)).to eq([ "ARE-001" ])
    expect(order.lines.sole).to have_attributes(gross_cents: 22_475, discount_cents: 2_248, net_cents: 20_227)
  end

  it "changes the supplier copy when the supplier changes" do
    other = supplier_for(organization, name: "Outra Distribuidora")

    update(supplier: other)

    expect(order.reload).to have_attributes(supplier_id: other.id, supplier_name: "Outra Distribuidora")
  end

  it "refuses an edit based on an older revision, writing nothing" do
    update(lines: [ line_input(cimento, quantity: "1") ])

    result = update(order, revision: 0, lines: [ line_input(cimento, quantity: "99") ])

    expect(result.error).to eq(:stale)
    expect(result.details[:current_revision]).to eq(1)
    expect(order.reload.lines.sole.quantity).to eq(BigDecimal("1"))
  end

  it "refuses to edit an order that is no longer a draft, even through an instance loaded before it was approved" do
    stale_copy = Purchasing::Order.find(order.id)
    Purchasing::ApproveOrder.call(order:, actor:, revision: 0)

    result = update(stale_copy, revision: 0)

    expect(result.error).to eq(:invalid_transition)
    expect(order.reload.status).to eq("approved")
  end

  it "reports what is wrong and changes nothing" do
    result = update(lines: [ line_input(cimento, quantity: "abc") ])

    expect(result.error).to eq(:validation_failed)
    expect(result.details[:fields]).to eq("lines.0.quantity" => [ "not_a_number" ])
    expect(order.reload).to have_attributes(revision: 0)
    expect(order.lines.sole.quantity).to eq(BigDecimal("10"))
  end

  it "needs a whole-number revision" do
    expect(update(revision: nil).details[:fields]).to eq("revision" => [ "not_a_number" ])
  end
end

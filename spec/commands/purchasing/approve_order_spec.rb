require "rails_helper"

RSpec.describe Purchasing::ApproveOrder do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization) }
  let(:cimento) { orderable_product(organization, sku: "CIM-001", name: "Cimento") }
  let(:order) { create_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "200", unit_price_cents: 3_250, discount_bp: 200) ]) }

  before { set_current_tenant(organization) }

  def approve(order = self.order, revision: order.revision) = described_class.call(order:, actor:, revision:)

  it "approves a draft, stamping who and when, bumping the revision" do
    result = approve

    expect(result).to be_success
    expect(order.reload).to have_attributes(status: "approved", revision: 1, approved_by_user_id: actor.id, total_cents: 637_000)
    expect(order.approved_at).to be_within(5.seconds).of(Time.current)
    expect(Audit::Event.where(action: "purchase_order_approved").sole.field_changes).to include("status" => { "from" => "draft", "to" => "approved" })
  end

  it "freezes the product and factor as they are at approval" do
    conversion = cimento.unit_conversion
    conversion.update!(factor: BigDecimal("2"))
    cimento.update!(name: "Cimento CP II-32")

    approve

    expect(order.reload.lines.sole).to have_attributes(factor: BigDecimal("2"), product_name: "Cimento CP II-32")
  end

  it "refuses an approval based on an older revision, so an edit made in between is never approved unseen" do
    Purchasing::UpdateOrder.call(order:, actor:, revision: 0, supplier:, lines: [ line_input(cimento, quantity: "1") ], installments: 1, first_due_days: 30, interval_days: 30)

    result = approve(order, revision: 0)

    expect(result.error).to eq(:stale)
    expect(order.reload.status).to eq("draft")
  end

  it "cannot approve twice, nor a cancelled order" do
    approve
    expect(approve(order, revision: 1).error).to eq(:invalid_transition)

    other = create_order!(organization:, supplier:, actor:, lines: [ line_input(cimento) ])
    Purchasing::CancelOrder.call(order: other, actor:)
    expect(approve(other, revision: 1).error).to eq(:invalid_transition)
  end

  it "decides from the row under the lock, not from a stale instance" do
    stale_copy = Purchasing::Order.find(order.id)
    Purchasing::CancelOrder.call(order:, actor:)

    expect(approve(stale_copy, revision: 0).error).to eq(:invalid_transition)
    expect(order.reload.status).to eq("cancelled")
  end

  describe "what must still be true at approval" do
    it "refuses a zero price, an inactive product and an inactive supplier" do
      free = create_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, unit_price_cents: 0) ])
      expect(approve(free).details[:fields]).to eq("lines.0.unit_price_cents" => [ "must_be_positive" ])

      order
      cimento.update!(active: false)
      expect(approve.details[:fields]).to eq("lines.0.product_id" => [ "inactive" ])

      cimento.update!(active: true)
      supplier.update!(active: false)
      expect(approve.details[:fields]).to eq("supplier_id" => [ "inactive" ])
      expect(order.reload.status).to eq("draft")
    end

    it "refuses a product whose purchase conversion is gone" do
      order
      cimento.unit_conversion.destroy!

      expect(approve.details[:fields]).to eq("lines.0.product_id" => [ "conversion_missing" ])
    end
  end
end

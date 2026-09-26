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

  it "freezes the descriptive copies (name, sku, supplier) as they are at approval" do
    order
    cimento.update!(name: "Cimento CP II-32")
    supplier.update!(name: "Cimentos Bahia Ltda")

    approve

    expect(order.reload.lines.sole.product_name).to eq("Cimento CP II-32")
    expect(order).to have_attributes(supplier_name: "Cimentos Bahia Ltda", status: "approved")
  end

  it "never changes what the approver saw in money: a purchase unit or factor changed since the draft is refused, and saving the draft again shows it" do
    order # 200 SC at R$ 32,50, factor 1: 200 stock units at 32,50 each
    mil = create(:unit, organization:, code: "MIL", name: "Milheiro")
    cimento.unit_conversion.update!(purchase_unit: mil, factor: BigDecimal("1000"))

    result = approve

    expect(result.error).to eq(:validation_failed)
    expect(result.details[:fields]).to eq("lines.0.conversion" => [ "changed" ])
    expect(order.reload).to have_attributes(status: "draft", revision: 0)
    expect(order.lines.sole).to have_attributes(purchase_unit_code: "SC", factor: BigDecimal("1"), net_cents: 637_000)

    # Saving the draft again refreshes the copy and bumps the revision, so the approver sees the new terms
    Purchasing::UpdateOrder.call(order:, actor:, revision: 0, supplier:, lines: [ line_input(cimento, quantity: "200", unit_price_cents: 3_250, discount_bp: 200) ],
      installments: 1, first_due_days: 30, interval_days: 30)
    expect(approve(order, revision: 0).error).to eq(:stale)
    expect(approve(order, revision: 1)).to be_success
    expect(order.reload.lines.sole).to have_attributes(purchase_unit_code: "MIL", factor: BigDecimal("1000"), net_cents: 637_000)
  end

  it "refuses to approve an order that could never be received because it does not fit a stock movement" do
    other = orderable_product(organization, sku: "GRD-001", purchase_unit_code: "MIL", factor: "1000")
    draft = Purchasing::Order.new(organization:, created_by_user: actor, supplier:, installments: 1)
    Purchasing::OrderRules.copy_supplier(draft, supplier)
    result = Purchasing::BuildLines.call(order: draft, inputs: [ line_input(other, quantity: "999999999999.999", unit_price_cents: 1) ])

    expect(result.last).to eq("lines.0.quantity" => [ "too_large" ])
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

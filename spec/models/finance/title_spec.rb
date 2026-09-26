require "rails_helper"

RSpec.describe Finance::Title do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:product) { orderable_product(organization, sku: "CIM-001") }
  let(:receipt) do
    order = approved_order!(organization:, supplier:, actor:, lines: [ line_input(product, quantity: "10", unit_price_cents: 1_000) ], installments: 2)
    Purchasing::ReceiveGoods.call(
      organization:, actor:, order:, warehouse:, lines: [ { order_line_id: order.lines.sole.id, quantity: "10" } ],
      received_on: Time.current.in_time_zone(organization.time_zone).to_date.to_s, idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
    ).value
  end
  let(:title) { receipt.title }

  before { set_current_tenant(organization) }

  it "has the transition table of ADR 0017: open closes by cancelling, and a cancelled title is final" do
    expect(described_class::TRANSITIONS).to eq("open" => %w[cancelled], "cancelled" => [])
    expect(title.can_transition_to?("cancelled")).to be(true)
    title.transition_to!(:cancelled)
    expect(title.reload.status).to eq("cancelled")
    expect(title.can_transition_to?("open")).to be(false)
    expect { title.transition_to!(:open) }.to raise_error(HasStateMachine::InvalidTransition)
  end

  it "refuses to change its status any other way (invariant 5)" do
    expect(title.update(status: "cancelled")).to be(false)
    expect(title.errors[:status]).to include("can only change through a transition")
    expect(title.reload.status).to eq("open")
  end

  it "shows an installment's open amount as what has not been settled" do
    installment = title.installments.first

    expect(installment.open_cents).to eq(installment.amount_cents)
  end
end

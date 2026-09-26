require "rails_helper"

RSpec.describe "concurrent commands on one purchase order (ADR 0017, ADR 0004)" do
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # Nothing is cleaned up (audit_events is append-only and references the
  # organization and the actor); every example builds its own organization.
  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    @supplier = supplier_for(@organization)
    @product = orderable_product(@organization, sku: "CIM-001")
  end

  def new_order
    create_order!(organization: @organization, supplier: @supplier, actor: @actor, lines: [ line_input(@product) ])
  end

  # Approve then cancel is legal, cancel then approve is not, so whichever gets
  # the lock first the order ends cancelled, the cancellation always succeeds,
  # and an approval either ran first or was refused: never an approved order
  # after a cancellation.
  it "always ends an order cancelled when an approval and a cancellation race" do
    order = new_order

    approval, cancellation = run_concurrently(
      lambda do
        set_current_tenant(@organization)
        Purchasing::ApproveOrder.call(order: Purchasing::Order.find(order.id), actor: @actor, revision: 0)
      end,
      lambda do
        set_current_tenant(@organization)
        Purchasing::CancelOrder.call(order: Purchasing::Order.find(order.id), actor: @actor)
      end
    )

    expect(cancellation).to be_success
    expect(approval.success? || approval.error == :invalid_transition).to be(true)
    set_current_tenant(@organization)
    expect(order.reload.status).to eq("cancelled")
  end

  it "lets exactly one of two approvals of the same revision succeed" do
    order = new_order

    results = run_concurrently(*Array.new(2) do
      lambda do
        set_current_tenant(@organization)
        Purchasing::ApproveOrder.call(order: Purchasing::Order.find(order.id), actor: @actor, revision: 0)
      end
    end)

    expect(results.map(&:success?)).to contain_exactly(true, false)
    expect(results.reject(&:success?).sole.error).to be_in(%i[invalid_transition stale])
  end

  it "numbers four orders created at once one to four, with no gap" do
    orders = run_concurrently(*Array.new(4) do
      lambda do
        set_current_tenant(@organization)
        create_order!(organization: @organization, supplier: @supplier, actor: @actor, lines: [ line_input(@product) ])
      end
    end)

    expect(orders.map(&:number).sort).to eq([ 1, 2, 3, 4 ])
  end
end

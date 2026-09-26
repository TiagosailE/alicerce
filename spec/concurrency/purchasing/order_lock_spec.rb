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

  def edit_lines(order, quantity)
    lambda do
      set_current_tenant(@organization)
      Purchasing::UpdateOrder.call(
        order: Purchasing::Order.find(order.id), actor: @actor, revision: 0, supplier: @supplier,
        lines: [ line_input(@product, quantity:) ], installments: 1, first_due_days: 30, interval_days: 30
      )
    end
  end

  # The ADR 0015 case: two people edit the same draft from the same read.
  it "lets exactly one of two edits made from the same revision win, and answers the other stale" do
    order = new_order

    results = run_concurrently(edit_lines(order, "11"), edit_lines(order, "22"))

    expect(results.map(&:success?)).to contain_exactly(true, false)
    expect(results.reject(&:success?).sole.error).to eq(:stale)
    set_current_tenant(@organization)
    expect(order.reload.revision).to eq(1)
    expect(order.lines.sole.quantity).to eq(BigDecimal(results.find(&:success?).value.lines.sole.quantity))
  end

  it "lets exactly one of an edit and an approval made from the same revision win, and an approved order keeps the lines it was approved with" do
    order = new_order

    edit, approval = run_concurrently(
      edit_lines(order, "11"),
      lambda do
        set_current_tenant(@organization)
        Purchasing::ApproveOrder.call(order: Purchasing::Order.find(order.id), actor: @actor, revision: 0)
      end
    )

    expect([ edit.success?, approval.success? ]).to contain_exactly(true, false)
    expect((edit.success? ? edit : approval).success?).to be(true)
    expect((edit.success? ? approval : edit).error).to be_in(%i[stale invalid_transition])
    set_current_tenant(@organization)
    order.reload
    expect(order.status).to eq(approval.success? ? "approved" : "draft")
    # Approved from revision 0: the lines are the ones the approver saw (10), never the edit's (11).
    expect(order.lines.sole.quantity).to eq(BigDecimal(approval.success? ? "10" : "11"))
  end

  it "decides a cancellation from the stored order, not from an instance loaded before it changed" do
    order = new_order
    stale_copy = Purchasing::Order.find(order.id)
    Purchasing::ApproveOrder.call(order: order, actor: @actor, revision: 0)
    Purchasing::CancelOrder.call(order: Purchasing::Order.find(order.id), actor: @actor)

    again = Purchasing::CancelOrder.call(order: stale_copy, actor: @actor)

    expect(again.error).to eq(:invalid_transition)
    expect(Audit::Event.where(subject_id: order.id, action: "purchase_order_cancelled").count).to eq(1)
  end
end

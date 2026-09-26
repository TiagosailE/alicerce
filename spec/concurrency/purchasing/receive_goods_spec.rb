require "rails_helper"

RSpec.describe "concurrent receipts (ADR 0004, ADR 0005, ADR 0017)" do
  # Real threads and committed rows: the races only exist across separate
  # Postgres transactions overlapping in time.
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # Nothing is cleaned up (receipts, movements and audit events are append-only
  # and reference the organization and the actor): every example builds its own
  # organization and gives its user a random email.
  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    @supplier = supplier_for(@organization)
    @warehouse = create(:warehouse, organization: @organization)
    @cement = orderable_product(@organization, sku: "CIM-001")
    @sand = orderable_product(@organization, sku: "ARE-001")
  end

  def new_order(*products, quantity: "200")
    approved_order!(organization: @organization, supplier: @supplier, actor: @actor,
      lines: products.map { |product| line_input(product, quantity:, unit_price_cents: 3_250, discount_bp: 200) })
  end

  # Each job runs on its own thread, so it sets its own tenant.
  def receive_job(order, quantities, key: SecureRandom.uuid, order_lines: nil)
    lambda do
      set_current_tenant(@organization)
      lines = order_lines || order.lines.to_a
      items = lines.zip(quantities).map { |line, quantity| { order_line_id: line.id, quantity: } }
      Purchasing::ReceiveGoods.call(
        organization: @organization, actor: @actor, order: Purchasing::Order.find(order.id), warehouse: @warehouse, lines: items,
        received_on: Time.current.in_time_zone(@organization.time_zone).to_date.to_s, idempotency_key: key,
        request_digest: Idempotency.digest(method: "POST", path: "/purchase_orders/#{order.id}/receipts", params: { items:, key: })
      )
    end
  end

  def balance(product)
    set_current_tenant(@organization)
    Inventory::Balance.find_by!(product_id: product.id, warehouse_id: @warehouse.id)
  end

  def expect_ledger_to_add_up(product)
    set_current_tenant(@organization)
    movements = Inventory::Movement.where(product_id: product.id, warehouse_id: @warehouse.id)
    expect(movements.sum(:quantity)).to eq(balance(product).on_hand)
    expect(movements.sum(:value_cents)).to eq(balance(product).value_cents)
  end

  it "lets only one of two receipts that together would over-receive a line through, and answers the other over_receipt" do
    order = new_order(@cement)

    results = run_concurrently(receive_job(order, [ "150" ]), receive_job(order, [ "150" ]))

    expect(results.map(&:success?)).to contain_exactly(true, false)
    loser = results.reject(&:success?).sole
    expect(loser.error).to eq(:validation_failed)
    expect(loser.details[:fields]).to eq("lines.0.quantity" => [ "over_receipt" ])
    set_current_tenant(@organization)
    expect(Purchasing::Receipt.count).to eq(1)
    expect(Finance::Title.count).to eq(1)
    expect(order.reload.lines.sole.received_quantity).to eq(BigDecimal("150"))
    expect(balance(@cement).on_hand).to eq(BigDecimal("150"))
    expect_ledger_to_add_up(@cement)
  end

  it "serializes two receipts that both fit: the line ends fully received and the amounts add up to it exactly" do
    order = new_order(@cement)

    results = run_concurrently(receive_job(order, [ "120" ]), receive_job(order, [ "80" ]))

    expect(results).to all(be_success)
    set_current_tenant(@organization)
    line = order.reload.lines.sole
    expect(order.status).to eq("received")
    expect(line).to have_attributes(received_quantity: BigDecimal("200"), received_gross_cents: 650_000, received_discount_cents: 13_000)
    expect(Purchasing::ReceiptLine.sum(:net_cents)).to eq(637_000)
    expect(Finance::Title.sum(:total_cents)).to eq(637_000)
    expect(Purchasing::Receipt.pluck(:number)).to contain_exactly(1, 2)
    expect_ledger_to_add_up(@cement)
  end

  it "writes one receipt when the same request is sent twice at once, and answers both with it" do
    order = new_order(@cement)
    key = "receive-#{SecureRandom.hex(6)}"
    job = receive_job(order, [ "50" ], key:)

    results = run_concurrently(job, job)

    expect(results).to all(be_success)
    expect(results.map { |result| result.value.id }.uniq.size).to eq(1)
    set_current_tenant(@organization)
    expect([ Purchasing::Receipt.count, Inventory::Movement.count, Finance::Title.count ]).to eq([ 1, 1, 1 ])
    expect(balance(@cement).on_hand).to eq(BigDecimal("50"))
  end

  it "never leaves a receipt on a cancelled order's line unrecorded: either the receipt came first and stays, or it is refused" do
    order = new_order(@cement)

    receipt, cancellation = run_concurrently(
      receive_job(order, [ "100" ]),
      lambda do
        set_current_tenant(@organization)
        Purchasing::CancelOrder.call(order: Purchasing::Order.find(order.id), actor: @actor)
      end
    )

    expect(cancellation).to be_success
    expect(receipt.success? || receipt.error == :invalid_transition).to be(true)
    set_current_tenant(@organization)
    expect(order.reload.status).to eq("cancelled")
    expect(Purchasing::Receipt.count).to eq(receipt.success? ? 1 : 0)
    expect(order.lines.sole.received_quantity).to eq(BigDecimal(receipt.success? ? "100" : "0"))
    expect(Inventory::Balance.where(product_id: @cement.id).sum(:on_hand)).to eq(BigDecimal(receipt.success? ? "100" : "0"))
  end

  it "keeps a balance's ledger exact when two orders receive the same product into the same warehouse at once" do
    first = new_order(@cement)
    second = new_order(@cement)

    results = run_concurrently(receive_job(first, [ "70" ]), receive_job(second, [ "30" ]))

    expect(results).to all(be_success)
    expect(balance(@cement)).to have_attributes(on_hand: BigDecimal("100"), value_cents: 70 * 3_185 + 30 * 3_185)
    expect_ledger_to_add_up(@cement)
    set_current_tenant(@organization)
    expect(Inventory::Movement.order(:id).map(&:on_hand_after)).to contain_exactly(BigDecimal("70"), BigDecimal("100")).or contain_exactly(BigDecimal("30"), BigDecimal("100"))
  end

  it "does not deadlock two receipts that reach the same two balances from opposite ends" do
    5.times do
      forward = new_order(@cement, @sand)
      backward = new_order(@sand, @cement)

      results = run_concurrently(receive_job(forward, %w[10 10]), receive_job(backward, %w[10 10]))

      expect(results).to all(be_success)
    end
    expect_ledger_to_add_up(@cement)
    expect_ledger_to_add_up(@sand)
  end

  it "keeps the ledger exact when a receipt and a stock count hit the same balance at once" do
    order = new_order(@cement)

    receipt, count = run_concurrently(
      receive_job(order, [ "50" ]),
      lambda do
        set_current_tenant(@organization)
        Inventory::AdjustStock.call(
          organization: @organization, actor: @actor, product: @cement, warehouse: @warehouse, counted_quantity: "10", expected_on_hand: "0",
          reason: "opening_balance", unit_cost_cents: "3000", idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
        )
      end
    )

    expect(receipt).to be_success
    expect(count.success? || count.error == :stale).to be(true)
    expect_ledger_to_add_up(@cement)
    expect(balance(@cement).on_hand).to eq(BigDecimal(count.success? ? "60" : "50"))
  end

  it "answers conflict_retry and writes nothing when another transaction holds the order past the lock timeout" do
    order = new_order(@cement)
    held = Queue.new
    release = Queue.new
    holder = Thread.new do
      set_current_tenant(@organization)
      ApplicationRecord.transaction do
        Purchasing::Order.lock("FOR NO KEY UPDATE").find(order.id)
        held << true
        release.pop
      end
    end
    held.pop
    stub_const("Purchasing::ReceiveGoods::LOCK_TIMEOUT", "150ms")

    result = receive_job(order, [ "10" ], key: "receive-timeout-1").call
    release << true
    holder.join

    expect(result.error).to eq(:conflict_retry)
    set_current_tenant(@organization)
    expect([ Purchasing::Receipt.count, Inventory::Movement.count, Finance::Title.count ]).to eq([ 0, 0, 0 ])
    expect(IdempotencyKey.where(key: "receive-timeout-1")).to be_empty
    # The same request, once the order is free, goes through with the same key.
    expect(receive_job(order, [ "10" ], key: "receive-timeout-1").call).to be_success
  end
end

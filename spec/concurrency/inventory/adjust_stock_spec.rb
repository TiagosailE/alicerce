require "rails_helper"

RSpec.describe "concurrent stock adjustments (ADR 0004, ADR 0005, ADR 0016)" do
  # Real threads and committed rows: the lost update only exists across
  # separate Postgres transactions actually overlapping in time.
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # Nothing is cleaned up: inventory_movements is append-only (ADR 0016) and
  # references the product and the warehouse by a real foreign key, so neither
  # can be deleted afterwards, and audit_events references the organization and
  # the actor (ADR 0010). Every example builds its own organization and gives
  # its user a random email, so a later run never collides with the leftovers.
  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    @product = create(:product, organization: @organization)
    @warehouse = create(:warehouse, organization: @organization)
  end

  def on_hand_now
    set_current_tenant(@organization)
    balance = Inventory::Balance.find_by(product_id: @product.id, warehouse_id: @warehouse.id)
    balance ? balance.on_hand.to_s("F") : "0"
  end

  def adjust(counted, expected: nil, unit_cost: nil, key: SecureRandom.uuid, digest: SecureRandom.hex(16), reason: "count")
    set_current_tenant(@organization)
    Inventory::AdjustStock.call(
      organization: @organization, actor: @actor, product: @product, warehouse: @warehouse,
      counted_quantity: counted, expected_on_hand: expected || on_hand_now, reason:, unit_cost_cents: unit_cost,
      idempotency_key: key, request_digest: digest
    )
  end

  # An operator's client: looks at the balance, counts, and when the answer is
  # stale looks again (the SPA reloads and asks for a new count).
  def count_with_retries(counted, attempts: 40)
    attempts.times do
      result = adjust(counted)
      return result unless result.error == :stale
    end
    raise "never got a turn"
  end

  def movements
    set_current_tenant(@organization)
    Inventory::Movement.where(product_id: @product.id, warehouse_id: @warehouse.id).order(:id).to_a
  end

  def balance
    set_current_tenant(@organization)
    Inventory::Balance.find_by!(product_id: @product.id, warehouse_id: @warehouse.id)
  end

  it "serializes counts on one balance, so every movement starts exactly where the previous one ended" do
    expect(adjust("100", reason: "opening_balance", unit_cost: "10")).to be_success

    # Groups of four: each thread holds a database connection, and the pool
    # holds five.
    counts = %w[40 90 10 60 0 75 20 100 55 5 30 80]
    results = counts.each_slice(4).flat_map do |group|
      run_concurrently(*group.map { |counted| -> { count_with_retries(counted) } })
    end

    expect(results).to all(be_success)
    ledger = movements
    # The lost-update detector: a movement that read a stale balance breaks the chain.
    ledger.each_cons(2) do |previous, current|
      expect(previous.on_hand_after + current.quantity).to eq(current.on_hand_after)
      expect(previous.value_after_cents + current.value_cents).to eq(current.value_after_cents)
    end
    expect(ledger.sum(&:quantity)).to eq(balance.on_hand)
    expect(ledger.sum(&:value_cents)).to eq(balance.value_cents)
    expect(balance.on_hand).to eq(ledger.last.on_hand_after)
    expect(balance.on_hand).to be >= 0
  end

  it "lets exactly one of four operators who saw the same balance count it, and refuses the other three as stale" do
    expect(adjust("100", reason: "opening_balance", unit_cost: "10")).to be_success

    results = run_concurrently(*%w[90 80 70 60].map { |counted| -> { adjust(counted, expected: "100.000") } })

    expect(results.count(&:success?)).to eq(1)
    expect(results.reject(&:success?).map(&:error)).to all(eq(:stale))
    expect(movements.size).to eq(2)
    expect(%w[90 80 70 60]).to include(balance.on_hand.to_i.to_s)
    expect(results.reject(&:success?).map { |result| result.details[:current_on_hand] }.uniq.size).to eq(1)
  end

  it "applies one effect when the same request arrives twice at once" do
    key = SecureRandom.uuid
    digest = SecureRandom.hex(16)

    results = run_concurrently(
      -> { adjust("10", expected: "0", unit_cost: "84.99", reason: "opening_balance", key:, digest:) },
      -> { adjust("10", expected: "0", unit_cost: "84.99", reason: "opening_balance", key:, digest:) }
    )

    expect(results).to all(be_success)
    expect(movements.size).to eq(1)
    expect(results.map { |result| result.value.movement.id }.uniq.size).to eq(1)
    expect(balance.on_hand).to eq(BigDecimal("10"))
  end

  it "lets exactly one of two different requests win the same key" do
    key = SecureRandom.uuid

    results = run_concurrently(
      -> { adjust("10", expected: "0", unit_cost: "1", reason: "opening_balance", key:, digest: "digest-a") },
      -> { adjust("20", expected: "0", unit_cost: "1", reason: "opening_balance", key:, digest: "digest-b") }
    )

    expect(results.map(&:success?)).to contain_exactly(true, false)
    expect(results.reject(&:success?).sole.error).to eq(:idempotency_key_reused)
    expect(movements.size).to eq(1)
  end

  it "never lets a decrease and an increase of the same unit lose each other" do
    expect(adjust("50", reason: "opening_balance", unit_cost: "10")).to be_success

    results = run_concurrently(-> { count_with_retries("30") }, -> { count_with_retries("70") })

    expect(results).to all(be_success)
    ledger = movements
    expect(ledger.sum(&:quantity)).to eq(balance.on_hand)
    expect(ledger.sum(&:value_cents)).to eq(balance.value_cents)
    expect([ BigDecimal("30"), BigDecimal("70") ]).to include(balance.on_hand)
  end

  # The threads above overlap only when the scheduler happens to line them up,
  # so on an unlucky run a missing lock would still pass. This one forces it:
  # the first holds the balance's lock for a known time, and the second, which
  # starts only once that lock is held, must not get through before it ends.
  it "makes a second counter wait for the first to be done with the balance" do
    expect(adjust("100", reason: "opening_balance", unit_cost: "10")).to be_success
    locked = Queue.new
    hold_for = 0.5

    holder = Thread.new do
      set_current_tenant(@organization)
      ApplicationRecord.transaction do
        Inventory::Balance.lock_for(organization: @organization, pairs: [ [ @product.id, @warehouse.id ] ])
        locked << true
        sleep hold_for
      end
    end
    locked.pop
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = adjust("90", expected: "100.000", reason: "loss")
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    holder.join

    expect(result).to be_success
    expect(waited).to be >= hold_for * 0.6
  end
end

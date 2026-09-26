require "rails_helper"

RSpec.describe "concurrent stock adjustments (ADR 0004, ADR 0005)" do
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

  def adjust(counted, unit_cost: nil, key: SecureRandom.uuid, digest: SecureRandom.hex(16))
    set_current_tenant(@organization)
    Inventory::AdjustStock.call(
      organization: @organization, actor: @actor, product: @product, warehouse: @warehouse,
      counted_quantity: counted, reason: "count", unit_cost:, idempotency_key: key, request_digest: digest
    )
  end

  def balance
    set_current_tenant(@organization)
    Inventory::Balance.find_by!(product_id: @product.id, warehouse_id: @warehouse.id)
  end

  def movements
    set_current_tenant(@organization)
    Inventory::Movement.where(product_id: @product.id, warehouse_id: @warehouse.id).order(:id).to_a
  end

  it "serializes counts on one balance, so every movement starts exactly where the previous one ended" do
    expect(adjust("100", unit_cost: "10")).to be_success

    # Groups of four: each thread holds a database connection, and the pool
    # holds five.
    counts = %w[40 90 10 60 0 75 20 100 55 5 30 80]
    results = counts.each_slice(4).flat_map do |group|
      run_concurrently(*group.map { |counted| -> { adjust(counted) } })
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

  it "applies one effect when the same request arrives twice at once" do
    key = SecureRandom.uuid
    digest = SecureRandom.hex(16)

    results = run_concurrently(
      -> { adjust("10", unit_cost: "84.99", key:, digest:) },
      -> { adjust("10", unit_cost: "84.99", key:, digest:) }
    )

    expect(results).to all(be_success)
    expect(movements.size).to eq(1)
    expect(results.map { |result| result.value.movement.id }.uniq.size).to eq(1)
    expect(balance.on_hand).to eq(BigDecimal("10"))
  end

  it "lets exactly one of two different requests win the same key" do
    key = SecureRandom.uuid

    results = run_concurrently(
      -> { adjust("10", unit_cost: "1", key:, digest: "digest-a") },
      -> { adjust("20", unit_cost: "1", key:, digest: "digest-b") }
    )

    expect(results.map(&:success?)).to contain_exactly(true, false)
    expect(results.reject(&:success?).sole.error).to eq(:idempotency_key_reused)
    expect(movements.size).to eq(1)
  end

  it "never lets a decrease and an increase of the same unit lose each other" do
    expect(adjust("50", unit_cost: "10")).to be_success

    results = run_concurrently(-> { adjust("30") }, -> { adjust("70") })

    expect(results).to all(be_success)
    ledger = movements
    expect(ledger.sum(&:quantity)).to eq(balance.on_hand)
    expect(ledger.sum(&:value_cents)).to eq(balance.value_cents)
    expect([ BigDecimal("30"), BigDecimal("70") ]).to include(balance.on_hand)
  end
end

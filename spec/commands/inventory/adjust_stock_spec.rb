require "rails_helper"

RSpec.describe Inventory::AdjustStock do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:product) { create(:product, organization:) }
  let(:warehouse) { create(:warehouse, organization:) }

  before { set_current_tenant(organization) }

  def adjust(counted, reason: "count", unit_cost: nil, note: nil, key: SecureRandom.uuid, digest: nil, product: self.product, warehouse: self.warehouse)
    described_class.call(
      organization:, actor:, product:, warehouse:, counted_quantity: counted, reason:, note:, unit_cost:,
      idempotency_key: key, request_digest: digest || Idempotency.digest(method: "POST", path: "/stock_adjustments", params: { counted:, reason:, unit_cost:, note: })
    )
  end

  def balance = Inventory::Balance.find_by!(product_id: product.id, warehouse_id: warehouse.id)

  def expect_ledger_to_add_up
    movements = Inventory::Movement.where(product_id: product.id, warehouse_id: warehouse.id)
    expect(movements.sum(:quantity)).to eq(balance.on_hand)
    expect(movements.sum(:value_cents)).to eq(balance.value_cents)
  end

  describe "an opening balance" do
    it "enters stock at the stated unit cost, which becomes the last cost" do
      result = adjust("10", reason: "opening_balance", unit_cost: "84.99")

      expect(result).to be_success
      adjustment = result.value
      expect(adjustment.status).to eq(201)
      expect(adjustment.movement).to have_attributes(kind: "adjustment", reason: "opening_balance", quantity: BigDecimal("10"),
        value_cents: 850, on_hand_after: BigDecimal("10"), value_after_cents: 850, actor_user: actor)
      expect(balance).to have_attributes(on_hand: BigDecimal("10"), value_cents: 850, last_unit_cost: BigDecimal("84.99"))
    end

    it "refuses stock it cannot value instead of entering it at zero" do
      result = adjust("10")

      expect(result).not_to be_success
      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq("unit_cost" => [ "required" ])
      expect(Inventory::Movement.count).to eq(0)
    end
  end

  describe "later counts" do
    before { adjust("10", reason: "opening_balance", unit_cost: "84.99") }

    it "values an increase at the current average cost" do
      result = adjust("15")

      expect(result.value.movement).to have_attributes(quantity: BigDecimal("5"), value_cents: 425, on_hand_after: BigDecimal("15"), value_after_cents: 1275)
      expect(balance).to have_attributes(on_hand: BigDecimal("15"), value_cents: 1275, last_unit_cost: BigDecimal("84.99"))
    end

    it "moves the average when the increase carries its own cost" do
      adjust("20", unit_cost: "100")

      # 850 + 10 x 100 = 1850 over 20 units: the average is now 92.5
      expect(balance).to have_attributes(on_hand: BigDecimal("20"), value_cents: 1850, last_unit_cost: BigDecimal("100"))
    end

    it "values a decrease at the current average cost and stores it negative" do
      adjust("15")
      result = adjust("12", reason: "loss")

      expect(result.value.movement).to have_attributes(quantity: BigDecimal("-3"), value_cents: -255, on_hand_after: BigDecimal("12"), value_after_cents: 1020)
      expect(balance).to have_attributes(on_hand: BigDecimal("12"), value_cents: 1020)
    end

    it "rounds the value of a decrease half up" do
      # 10 units worth 850: taking 1 is 85; take a share that lands on .5 instead
      adjust("2", reason: "loss") # 850 x 8 / 10 = 680 out, 170 left over 2 units
      adjust("1", reason: "loss") # 170 x 1 / 2 = 85 exactly

      expect(balance).to have_attributes(on_hand: BigDecimal("1"), value_cents: 85)
      adjust("0.5", reason: "loss") # 85 x 0.5 / 1 = 42.5, half up is 43

      expect(balance.value_cents).to eq(42)
      expect(Inventory::Movement.order(:id).last.value_cents).to eq(-43)
    end

    it "takes all the remaining value when the decrease empties the balance" do
      adjust("3", reason: "loss") # 850 x 7 / 10 = 595 out, 255 left over 3 units
      result = adjust("0", reason: "damage")

      expect(result.value.movement).to have_attributes(quantity: BigDecimal("-3"), value_cents: -255, value_after_cents: 0)
      expect(balance).to have_attributes(on_hand: BigDecimal("0"), value_cents: 0)
    end

    it "does not accept a unit cost on a decrease" do
      result = adjust("5", reason: "loss", unit_cost: "50")

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq("unit_cost" => [ "not_applicable" ])
      expect(balance.on_hand).to eq(BigDecimal("10"))
    end

    it "values an increase from an emptied balance at the last cost" do
      adjust("0", reason: "damage")
      result = adjust("4", reason: "found")

      # 4 x 84.99 = 339.96
      expect(result.value.movement.value_cents).to eq(340)
      expect(balance).to have_attributes(on_hand: BigDecimal("4"), value_cents: 340)
    end

    it "writes nothing when the count matches the balance" do
      result = adjust("10")

      expect(result).to be_success
      expect(result.value).to have_attributes(movement: nil, status: 200)
      expect(Inventory::Movement.count).to eq(1)
      expect(balance).to have_attributes(on_hand: BigDecimal("10"), value_cents: 850)
    end

    it "keeps the ledger adding up to the balance across a sequence of adjustments" do
      %w[15 12 20 7 0 3].each_with_index do |counted, index|
        adjust(counted, reason: index.zero? ? "found" : "count", unit_cost: (index == 2 || index == 5 ? "91.37" : nil))
        expect_ledger_to_add_up
      end
    end
  end

  describe "a balance below zero" do
    it "is refused, since nothing yet settles it" do
      adjust("10", reason: "opening_balance", unit_cost: "84.99")
      balance.update!(negative_allowance: BigDecimal("20"), on_hand: BigDecimal("-2"), value_cents: -170)

      result = adjust("5")

      expect(result.error).to eq(:negative_balance)
    end
  end

  describe "input" do
    it "answers validation_failed with a kind per field and writes nothing" do
      result = adjust("1.2345", reason: "whim", unit_cost: "abc", note: "n" * 501, key: "short")

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq(
        "counted_quantity" => [ "too_many_decimals" ], "unit_cost" => [ "not_a_number" ],
        "reason" => [ "inclusion" ], "note" => [ "too_long" ], "idempotency_key" => [ "invalid" ]
      )
      expect(Inventory::Balance.count).to eq(0)
      expect(IdempotencyKey.count).to eq(0)
    end

    it "does not round a quantity that needs more than three places" do
      expect(adjust("10.0005", unit_cost: "1").details[:fields]).to eq("counted_quantity" => [ "too_many_decimals" ])
    end
  end

  describe "the audit trail" do
    it "records the adjustment with the note redacted" do
      adjust("10", reason: "opening_balance", unit_cost: "84.99", note: "Contagem do galpao, cliente Joao")

      event = Audit::Event.find_by!(action: "stock_adjusted")
      expect(event.actor_user_id).to eq(actor.id)
      expect(event.field_changes).to include(
        "reason" => "opening_balance", "quantity" => "10.000", "value_cents" => 850, "note" => "changed"
      )
      expect(event.field_changes.to_json).not_to include("Joao")
    end
  end

  describe "idempotency (ADR 0005)" do
    let(:key) { SecureRandom.uuid }
    let(:digest) { Idempotency.digest(method: "POST", path: "/stock_adjustments", params: { counted: "10" }) }

    it "replays the same request with the stored status and no second effect" do
      first = adjust("10", unit_cost: "84.99", key:, digest:)
      second = adjust("10", unit_cost: "84.99", key:, digest:)

      expect(second).to be_success
      expect(second.value.status).to eq(201)
      expect(second.value.movement.id).to eq(first.value.movement.id)
      expect(Inventory::Movement.count).to eq(1)
      expect(balance.on_hand).to eq(BigDecimal("10"))
    end

    it "rejects the same key used for a different request" do
      adjust("10", unit_cost: "84.99", key:, digest:)
      other = adjust("99", unit_cost: "84.99", key:, digest: Idempotency.digest(method: "POST", path: "/stock_adjustments", params: { counted: "99" }))

      expect(other.error).to eq(:idempotency_key_reused)
      expect(balance.on_hand).to eq(BigDecimal("10"))
    end

    it "does not remember a failed attempt, so the same key can be retried" do
      failed = adjust("10", key:, digest:)
      expect(failed.error).to eq(:validation_failed)
      expect(IdempotencyKey.count).to eq(0)

      retried = adjust("10", unit_cost: "84.99", key:, digest:)

      expect(retried).to be_success
      expect(Inventory::Movement.count).to eq(1)
    end

    it "remembers a count that matched, and replays it as one" do
      adjust("10", unit_cost: "84.99")
      first = adjust("10", key:, digest:)
      second = adjust("10", key:, digest:)

      expect(first.value.status).to eq(200)
      expect(second.value).to have_attributes(status: 200, movement: nil)
    end

    it "keeps keys apart per user" do
      other_user = create(:user)
      adjust("10", unit_cost: "84.99", key:, digest:)

      result = described_class.call(
        organization:, actor: other_user, product:, warehouse:, counted_quantity: "10", reason: "count", unit_cost: "84.99",
        idempotency_key: key, request_digest: digest
      )

      expect(result.value.status).to eq(200)
    end
  end
end

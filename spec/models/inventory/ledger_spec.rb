require "rails_helper"

RSpec.describe Inventory::Ledger do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:product) { create(:product, organization:) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:balance) { Inventory::Balance.lock_for(organization:, pairs: [ [ product.id, warehouse.id ] ]).sole }

  before { set_current_tenant(organization) }

  def post(quantity:, value_cents:, **options)
    described_class.post(balance:, kind: "adjustment", quantity: BigDecimal(quantity), value_cents:, actor:, reason: "count", **options)
  end

  describe ".post" do
    it "writes the movement and moves the balance by the same quantity and value" do
      movement = post(quantity: "10", value_cents: 850, last_unit_cost: BigDecimal("84.99"))

      expect(movement).to have_attributes(quantity: BigDecimal("10"), value_cents: 850, on_hand_after: BigDecimal("10"), value_after_cents: 850)
      expect(balance.reload).to have_attributes(on_hand: BigDecimal("10"), value_cents: 850, last_unit_cost: BigDecimal("84.99"))
    end

    it "keeps the last cost when none is given, and chains one movement after the next" do
      post(quantity: "10", value_cents: 850, last_unit_cost: BigDecimal("84.99"))
      second = post(quantity: "-3", value_cents: -255)

      expect(second).to have_attributes(on_hand_after: BigDecimal("7"), value_after_cents: 595)
      expect(balance.reload.last_unit_cost).to eq(BigDecimal("84.99"))
    end

    it "posts from the row as it is under the lock, not from a stale copy the caller loaded earlier" do
      first_copy = balance
      second_copy = Inventory::Balance.find(first_copy.id) # loaded before the first line posts

      post(quantity: "10", value_cents: 850)
      # The same product's second line, through the copy that still says 0.
      movement = described_class.post(balance: second_copy, kind: "adjustment", quantity: BigDecimal("5"), value_cents: 425,
        actor:, reason: "count")

      expect(movement).to have_attributes(on_hand_after: BigDecimal("15"), value_after_cents: 1275)
      expect(balance.reload).to have_attributes(on_hand: BigDecimal("15"), value_cents: 1275)
      expect(second_copy).to have_attributes(on_hand: BigDecimal("15"), value_cents: 1275)
    end

    it "refuses a value past the cap instead of letting the database refuse it" do
      expect { post(quantity: "1", value_cents: described_class::VALUE_CAP_CENTS + 1) }.to raise_error(ArgumentError, /out of range/)
      expect(Inventory::Movement.count).to eq(0)
    end
  end

  describe ".fits?" do
    it "accepts up to the cap on the movement and on the running total, and no more" do
      cap = described_class::VALUE_CAP_CENTS
      expect(described_class.fits?(balance, cap)).to be(true)
      expect(described_class.fits?(balance, -cap)).to be(true)
      expect(described_class.fits?(balance, cap + 1)).to be(false)

      balance.update!(on_hand: 1, value_cents: cap)
      expect(described_class.fits?(balance, 1)).to be(false)
      expect(described_class.fits?(balance, -1)).to be(true)
    end
  end
end

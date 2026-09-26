require "rails_helper"

RSpec.describe Inventory::Costing do
  describe ".round_half_up" do
    it "rounds exactly half up" do
      expect(described_class.round_half_up(Rational(5, 2))).to eq(3)
      expect(described_class.round_half_up(Rational(4999, 2000))).to eq(2)
      expect(described_class.round_half_up(Rational(1, 2))).to eq(1)
      expect(described_class.round_half_up(Rational(0))).to eq(0)
    end

    it "refuses a negative value, so the sign is applied by the caller" do
      expect { described_class.round_half_up(Rational(-1, 2)) }.to raise_error(ArgumentError)
    end
  end

  describe ".value_at_unit_cost" do
    it "values a quantity at a unit cost that is a fraction of a cent" do
      # 10 bricks at 84.99 cents each: 849.9 cents
      expect(described_class.value_at_unit_cost(BigDecimal("10"), BigDecimal("84.99"))).to eq(850)
    end

    it "keeps three decimal places of quantity exactly" do
      # 0.333 m3 of sand at 1234.5 cents: 411.0885 cents
      expect(described_class.value_at_unit_cost(BigDecimal("0.333"), BigDecimal("1234.5"))).to eq(411)
    end
  end

  describe ".value_at_average_cost" do
    it "takes a proportional share of the balance value" do
      expect(described_class.value_at_average_cost(1275, BigDecimal("3"), BigDecimal("15"))).to eq(255)
    end

    it "rounds half up when the share is not a whole number of cents" do
      expect(described_class.value_at_average_cost(5, BigDecimal("1"), BigDecimal("2"))).to eq(3)
      expect(described_class.value_at_average_cost(100, BigDecimal("1"), BigDecimal("3"))).to eq(33)
    end

    it "does not lose precision on a large value" do
      expect(described_class.value_at_average_cost(9_000_000_000_007, BigDecimal("1"), BigDecimal("3"))).to eq(3_000_000_000_002)
    end
  end
end

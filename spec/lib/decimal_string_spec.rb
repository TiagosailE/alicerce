require "rails_helper"

RSpec.describe DecimalString do
  describe ".format" do
    it "always carries every place" do
      expect(described_class.format(BigDecimal("1000"), 6)).to eq("1000.000000")
      expect(described_class.format(BigDecimal("12.5"), 3)).to eq("12.500")
      expect(described_class.format(BigDecimal("0"), 3)).to eq("0.000")
    end

    it "keeps the sign" do
      expect(described_class.format(BigDecimal("-4"), 3)).to eq("-4.000")
    end
  end

  describe ".parse" do
    def parse(raw, places: 3, integer_digits: 12) = described_class.parse(raw, places:, integer_digits:)

    it "reads a plain decimal" do
      expect(parse("12.5")).to eq([ BigDecimal("12.5"), nil ])
      expect(parse("0")).to eq([ BigDecimal("0"), nil ])
      expect(parse("999999999999.999")).to eq([ BigDecimal("999999999999.999"), nil ])
    end

    it "names what is wrong instead of rounding" do
      expect(parse("1.2345")).to eq([ nil, :too_many_decimals ])
      expect(parse("-1")).to eq([ nil, :negative ])
      expect(parse("abc")).to eq([ nil, :not_a_number ])
      expect(parse("1,5")).to eq([ nil, :not_a_number ])
      expect(parse("")).to eq([ nil, :not_a_number ])
      expect(parse("1e3")).to eq([ nil, :not_a_number ])
      expect(parse("1000000000000")).to eq([ nil, :too_large ])
    end

    it "accepts a number sent as a JSON number" do
      expect(parse(12)).to eq([ BigDecimal("12"), nil ])
    end
  end
end

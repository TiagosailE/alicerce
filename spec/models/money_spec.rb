require "rails_helper"

RSpec.describe Money do
  describe ".allocate" do
    it "gives the extra cents to the first parts (ADR 0006's worked numbers)" do
      expect(described_class.allocate(10_000, 3)).to eq([ 3_334, 3_333, 3_333 ])
      expect(described_class.allocate(10_001, 3)).to eq([ 3_334, 3_334, 3_333 ])
      expect(described_class.allocate(100, 7)).to eq([ 15, 15, 14, 14, 14, 14, 14 ])
    end

    it "is one part for one, and zeros past the total" do
      expect(described_class.allocate(500, 1)).to eq([ 500 ])
      expect(described_class.allocate(2, 5)).to eq([ 1, 1, 0, 0, 0 ])
      expect(described_class.allocate(0, 3)).to eq([ 0, 0, 0 ])
    end

    it "always adds up to the total, with parts that differ by at most a cent and never grow" do
      [ 0, 1, 2, 99, 100, 101, 9_999, 10_001, 123_457, 10**12 + 7 ].each do |total|
        (1..24).each do |parts|
          allocated = described_class.allocate(total, parts)

          expect(allocated.size).to eq(parts)
          expect(allocated.sum).to eq(total)
          expect(allocated.max - allocated.min).to be <= 1
          expect(allocated).to eq(allocated.sort.reverse)
        end
      end
    end

    it "never makes a zero part when the parts are capped at the cents to split, as a payable's installments are" do
      [ 1, 2, 3, 5, 24, 25, 382_201, 10**15 ].each do |total|
        (1..24).each do |asked|
          allocated = described_class.allocate(total, [ asked, total ].min)

          expect(allocated.min).to be >= 1
          expect(allocated.sum).to eq(total)
        end
      end
    end

    it "refuses what cannot be split" do
      expect { described_class.allocate(-1, 3) }.to raise_error(ArgumentError)
      expect { described_class.allocate(100, 0) }.to raise_error(ArgumentError)
    end
  end
end

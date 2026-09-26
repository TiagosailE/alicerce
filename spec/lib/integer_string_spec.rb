require "rails_helper"

RSpec.describe IntegerString do
  it "reads integers and plain base-10 digit strings" do
    expect(described_class.parse(30)).to eq(30)
    expect(described_class.parse("30")).to eq(30)
    expect(described_class.parse("-5")).to eq(-5)
    expect(described_class.parse("010")).to eq(10)
  end

  it "refuses what Kernel#Integer would read as something else, and anything that is not a number" do
    [ "0x1A", "1_0", "1e3", "1.9", 1.9, " 5", "5 ", "", nil, [ 1 ], { a: 1 }, true, "9" * 19 ].each do |raw|
      expect(described_class.parse(raw)).to be_nil, "expected #{raw.inspect} to be refused"
    end
  end
end

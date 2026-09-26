require "rails_helper"

RSpec.describe Purchasing::ReceiptMath do
  # Just the columns the arithmetic reads, with the received figures a command
  # keeps on the line and advances after each receipt.
  Line = Struct.new(:quantity, :unit_price_cents, :discount_bp, :factor, :received_quantity, :received_gross_cents,
    :received_discount_cents, :received_stock_quantity, keyword_init: true) do
    def self.of(quantity:, unit_price_cents:, discount_bp: 0, factor: "1")
      new(quantity: BigDecimal(quantity), unit_price_cents:, discount_bp:, factor: BigDecimal(factor), received_quantity: BigDecimal("0"),
        received_gross_cents: 0, received_discount_cents: 0, received_stock_quantity: BigDecimal("0"))
    end

    def total_gross = Inventory::Costing.value_at_unit_cost(quantity, unit_price_cents)
    def total_discount = Inventory::Costing.round_half_up(Rational(total_gross * discount_bp, 10_000))
  end

  # Receives each quantity in turn, advancing the line the way ReceiveGoods does.
  def receive_all(line, quantities)
    quantities.map do |quantity|
      quantity = BigDecimal(quantity)
      amounts = described_class.call(line:, quantity:)
      line.received_quantity += quantity
      line.received_gross_cents += amounts.gross_cents
      line.received_discount_cents += amounts.discount_cents
      line.received_stock_quantity += amounts.stock_quantity
      amounts
    end
  end

  it "takes a receipt of part of a line at the line's own rates (ADR 0017's worked example)" do
    line = Line.of(quantity: "200", unit_price_cents: 3_250, discount_bp: 200)

    first, second = receive_all(line, %w[120 80])

    expect(first).to have_attributes(gross_cents: 390_000, discount_cents: 7_800, net_cents: 382_200, stock_quantity: BigDecimal("120"))
    # The last receipt lands on the line's totals without a completion special case.
    expect(second).to have_attributes(gross_cents: 260_000, discount_cents: 5_200, net_cents: 254_800, stock_quantity: BigDecimal("80"))
    expect(first.net_cents + second.net_cents).to eq(637_000)
  end

  it "never yields a negative discount where ADR 0006's completion rule did (R$ 32,25 at 2%, one bag at a time)" do
    line = Line.of(quantity: "200", unit_price_cents: 3_225, discount_bp: 200)

    amounts = receive_all(line, Array.new(200) { "1" })

    expect(amounts.map(&:discount_cents)).to all(be >= 0)
    expect(amounts.sum(&:discount_cents)).to eq(line.total_discount)
    expect(amounts.sum(&:gross_cents)).to eq(line.total_gross)
    expect(line.total_discount).to eq(12_900)
  end

  it "keeps a small last receipt valid (sand at R$ 89,90 with 10%: 0.5, 0.5, 0.5 and 0.001 m3)" do
    line = Line.of(quantity: "1.501", unit_price_cents: 8_990, discount_bp: 1_000)

    amounts = receive_all(line, %w[0.5 0.5 0.5 0.001])

    expect(amounts.map(&:gross_cents)).to all(be >= 0)
    expect(amounts.map(&:discount_cents)).to all(be >= 0)
    expect(amounts.each_index.all? { |i| amounts[i].discount_cents <= amounts[i].gross_cents }).to be(true)
    expect(amounts.sum(&:gross_cents)).to eq(line.total_gross)
    expect(amounts.sum(&:discount_cents)).to eq(line.total_discount)
  end

  it "converts to stock units cumulatively, so the parts add up to the line's stock quantity" do
    packs = Line.of(quantity: "3", unit_price_cents: 1_000, factor: "0.333333")
    amounts = receive_all(packs, %w[1 1 1])
    expect(amounts.sum(&:stock_quantity)).to eq(described_class.stock_quantity(BigDecimal("3"), BigDecimal("0.333333")))
    expect(described_class.stock_quantity(BigDecimal("3"), BigDecimal("0.333333"))).to eq(BigDecimal("1"))

    kilos = Line.of(quantity: "1.5", unit_price_cents: 100, factor: "0.001")
    amounts = receive_all(kilos, %w[0.5 0.5 0.5])
    expect(amounts.sum(&:stock_quantity)).to eq(BigDecimal("0.002"))
    expect(amounts.map(&:stock_quantity)).to eq([ BigDecimal("0.001"), BigDecimal("0"), BigDecimal("0.001") ])
  end

  it "makes a free line (100% off) worth nothing without a negative amount" do
    line = Line.of(quantity: "10", unit_price_cents: 500, discount_bp: 10_000)

    amounts = receive_all(line, %w[3 7])

    expect(amounts.map(&:net_cents)).to eq([ 0, 0 ])
    expect(amounts.sum(&:discount_cents)).to eq(5_000)
  end

  it "adds up to the line for any partition, with no amount out of range (property over random lines)" do
    random = Random.new(20_260_926)
    500.times do
      quantity = BigDecimal(random.rand(1..5_000_000)) / 1000
      line = Line.of(quantity: quantity.to_s("F"), unit_price_cents: random.rand(0..2_000_000), discount_bp: random.rand(0..10_000),
        factor: [ "1", "1000", "0.001", "0.333333", "12", "0.5" ].sample(random: random))
      cuts = Array.new(random.rand(0..6)) { random.rand(1..(quantity * 1000).to_i) }.sort.uniq
      bounds = [ 0, *cuts, (quantity * 1000).to_i ].uniq
      parts = bounds.each_cons(2).map { |from, to| (BigDecimal(to - from) / 1000).to_s("F") }

      amounts = receive_all(line, parts)

      expect(amounts.map(&:gross_cents)).to all(be >= 0)
      expect(amounts.map(&:discount_cents)).to all(be >= 0)
      expect(amounts.map(&:net_cents)).to all(be >= 0)
      expect(amounts.sum(&:gross_cents)).to eq(line.total_gross)
      expect(amounts.sum(&:discount_cents)).to eq(line.total_discount)
      expect(amounts.sum(&:stock_quantity)).to eq(described_class.stock_quantity(quantity, line.factor))
      expect(amounts.map(&:stock_quantity)).to all(be >= 0)
    end
  end
end

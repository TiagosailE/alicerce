require "rails_helper"

RSpec.describe Purchasing::OrderLine do
  let(:organization) { create(:organization) }
  let(:order) { create(:purchase_order, organization:) }
  let(:product) { orderable_product(organization, sku: "CIM-001") }

  before { set_current_tenant(organization) }

  def line(quantity:, unit_price_cents:, discount_bp: 0)
    described_class.new(organization:, order:, position: 1, quantity:, unit_price_cents:, discount_bp:).tap do |line|
      line.copy_from(product)
      line.validate
    end
  end

  describe "amounts (ADR 0017, worked numbers)" do
    it "works out gross, discount and net for 200 bags at R$ 32,50 with 2% off" do
      expect(line(quantity: "200", unit_price_cents: 3_250, discount_bp: 200))
        .to have_attributes(gross_cents: 650_000, discount_cents: 13_000, net_cents: 637_000)
    end

    it "rounds the discount half up: R$ 32,25 at 2% takes 65 cents off a single bag, not 64" do
      expect(line(quantity: "1", unit_price_cents: 3_225, discount_bp: 200))
        .to have_attributes(gross_cents: 3_225, discount_cents: 65, net_cents: 3_160)
    end

    it "keeps three places of quantity exactly" do
      # 0.333 m3 at R$ 12,345 per m3 (1.234,5 cents): 411.0885 cents, half up 411
      expect(line(quantity: "0.333", unit_price_cents: 1_235)).to have_attributes(gross_cents: 411)
    end

    it "lets a 100% discount make a free line, and a zero price a zero line" do
      expect(line(quantity: "5", unit_price_cents: 1_000, discount_bp: 10_000)).to have_attributes(gross_cents: 5_000, discount_cents: 5_000, net_cents: 0)
      expect(line(quantity: "5", unit_price_cents: 0)).to have_attributes(gross_cents: 0, net_cents: 0)
    end
  end

  describe "validation" do
    it "refuses a quantity that is not positive, or has more than three places" do
      expect(line(quantity: "0", unit_price_cents: 100).errors.of_kind?(:quantity, :greater_than)).to be(true)
      expect(line(quantity: "1.0005", unit_price_cents: 100).errors.of_kind?(:quantity, :too_many_decimals)).to be(true)
    end

    it "refuses a discount outside 0 to 10000 basis points and a negative price" do
      expect(line(quantity: "1", unit_price_cents: 100, discount_bp: 10_001).errors.of_kind?(:discount_bp, :in)).to be(true)
      expect(line(quantity: "1", unit_price_cents: -1).errors.of_kind?(:unit_price_cents, :greater_than_or_equal_to)).to be(true)
    end

    it "refuses a gross past the cap instead of letting the database refuse it" do
      big = line(quantity: "999999999999", unit_price_cents: 10**13)

      expect(big.errors.of_kind?(:quantity, :too_large)).to be(true)
    end
  end

  describe "#copy_from" do
    it "copies the product's name, sku, purchase unit and factor as they are now" do
      product = orderable_product(organization, sku: "TIJ-001", name: "Tijolo", purchase_unit_code: "MIL", factor: "1000")

      copied = line(quantity: "5", unit_price_cents: 84_990).tap { |l| l.copy_from(product) }

      expect(copied).to have_attributes(product_sku: "TIJ-001", product_name: "Tijolo", purchase_unit_code: "MIL", stock_unit_code: "UN", factor: BigDecimal("1000"))
    end
  end

  it "knows what is left to receive" do
    expect(described_class.new(quantity: BigDecimal("200"), received_quantity: BigDecimal("120")).remaining_quantity).to eq(BigDecimal("80"))
  end
end

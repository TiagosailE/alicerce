require "rails_helper"

RSpec.describe Catalog::UnitConversion do
  let(:organization) { create(:organization) }

  it "requires a positive factor" do
    set_current_tenant(organization)
    conversion = build(:unit_conversion, organization:, factor: 0)

    expect(conversion).not_to be_valid
    expect(conversion.errors.of_kind?(:factor, :greater_than)).to be(true)
  end

  it "rejects a factor with more than six decimals instead of rounding it" do
    set_current_tenant(organization)
    conversion = build(:unit_conversion, organization:, factor: "1.0000004")

    expect(conversion).not_to be_valid
    expect(conversion.errors.of_kind?(:factor, :too_many_decimals)).to be(true)
  end

  it "rejects a factor the numeric(15,6) column cannot hold instead of failing in the database" do
    set_current_tenant(organization)
    conversion = build(:unit_conversion, organization:, factor: "1000000000")

    expect(conversion).not_to be_valid
    expect(conversion.errors.of_kind?(:factor, :less_than)).to be(true)
  end

  it "accepts exactly six decimals and the largest value the column holds" do
    set_current_tenant(organization)

    expect(build(:unit_conversion, organization:, factor: "0.000001")).to be_valid
    expect(build(:unit_conversion, organization:, factor: "999999999.999999")).to be_valid
  end

  it "allows only one conversion per product" do
    set_current_tenant(organization)
    product = create(:product, organization:)
    create(:unit_conversion, organization:, product:)
    duplicate = build(:unit_conversion, organization:, product:)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:product_id, :taken)).to be(true)
  end
end

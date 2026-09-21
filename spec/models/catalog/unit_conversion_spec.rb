require "rails_helper"

RSpec.describe Catalog::UnitConversion do
  let(:organization) { create(:organization) }

  it "requires a positive factor" do
    set_current_tenant(organization)
    conversion = build(:unit_conversion, organization:, factor: 0)

    expect(conversion).not_to be_valid
    expect(conversion.errors.of_kind?(:factor, :greater_than)).to be(true)
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

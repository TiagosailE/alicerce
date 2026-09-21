require "rails_helper"

RSpec.describe Catalog::Product do
  let(:organization) { create(:organization) }

  it "requires a sku and a name" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)
    product = build(:product, organization:, stock_unit: unit, sku: "", name: "")

    expect(product).not_to be_valid
    expect(product.errors.of_kind?(:sku, :blank)).to be(true)
    expect(product.errors.of_kind?(:name, :blank)).to be(true)
  end

  it "rejects a duplicate sku within the same organization, regardless of case" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)
    create(:product, organization:, stock_unit: unit, sku: "TIJ-001")
    duplicate = build(:product, organization:, stock_unit: unit, sku: "tij-001")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:sku, :taken)).to be(true)
  end

  it "does not require a category" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)
    product = build(:product, organization:, stock_unit: unit, category: nil)

    expect(product).to be_valid
  end

  it "rejects a category_id belonging to another organization" do
    other_organization = create(:organization)
    set_current_tenant(other_organization)
    other_category = create(:category, organization: other_organization)

    set_current_tenant(organization)
    unit = create(:unit, organization:)
    product = build(:product, organization:, stock_unit: unit, category_id: other_category.id)

    expect(product).not_to be_valid
    expect(product.errors.of_kind?(:category, :not_found)).to be(true)
  end

  it "rejects a category_id that does not exist at all" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)
    product = build(:product, organization:, stock_unit: unit, category_id: 0)

    expect(product).not_to be_valid
    expect(product.errors.of_kind?(:category, :not_found)).to be(true)
  end
end

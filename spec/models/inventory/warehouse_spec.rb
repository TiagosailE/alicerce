require "rails_helper"

RSpec.describe Inventory::Warehouse do
  let(:organization) { create(:organization) }

  it "requires a name" do
    set_current_tenant(organization)
    warehouse = build(:warehouse, organization:, name: "")

    expect(warehouse).not_to be_valid
    expect(warehouse.errors.of_kind?(:name, :blank)).to be(true)
  end

  it "rejects a duplicate name within the same organization, regardless of case" do
    set_current_tenant(organization)
    create(:warehouse, organization:, name: "Loja")
    duplicate = build(:warehouse, organization:, name: "LOJA")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:name, :taken)).to be(true)
  end
end

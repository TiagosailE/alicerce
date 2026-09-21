require "rails_helper"

RSpec.describe Inventory::UpdateWarehouse do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "updates the warehouse's fields" do
    warehouse = create(:warehouse, organization:, name: "Loja")

    result = described_class.call(warehouse:, attributes: { name: "Loja centro", active: true }, actor:)

    expect(result).to be_success
    expect(warehouse.reload.name).to eq("Loja centro")
  end

  it "can deactivate a warehouse" do
    warehouse = create(:warehouse, organization:, active: true)

    result = described_class.call(warehouse:, attributes: { name: warehouse.name, active: false }, actor:)

    expect(result).to be_success
    expect(warehouse.reload.active).to be(false)
  end

  it "fails with validation_failed for a duplicate name" do
    create(:warehouse, organization:, name: "Pátio")
    warehouse = create(:warehouse, organization:, name: "Loja")

    result = described_class.call(warehouse:, attributes: { name: "pátio", active: true }, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(warehouse.reload.name).to eq("Loja")
  end
end

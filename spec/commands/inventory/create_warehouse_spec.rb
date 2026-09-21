require "rails_helper"

RSpec.describe Inventory::CreateWarehouse do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "creates a warehouse" do
    result = described_class.call(organization:, name: "Loja", actor:)

    expect(result).to be_success
    expect(result.value).to be_persisted
    expect(result.value.name).to eq("Loja")
  end

  it "records an audit event" do
    described_class.call(organization:, name: "Loja", actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("warehouse_created")
    expect(event.field_changes).to eq("name" => "Loja")
  end

  it "fails with validation_failed for a duplicate name" do
    create(:warehouse, organization:, name: "Loja")

    result = described_class.call(organization:, name: "loja", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Inventory::Warehouse.count).to eq(1)
  end
end

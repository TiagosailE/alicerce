require "rails_helper"

RSpec.describe Catalog::CreateCategory do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "creates a category" do
    result = described_class.call(organization:, name: "Ferragens", actor:)

    expect(result).to be_success
    expect(result.value).to be_persisted
    expect(result.value.name).to eq("Ferragens")
  end

  it "records an audit event" do
    described_class.call(organization:, name: "Ferragens", actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("category_created")
    expect(event.field_changes).to eq("name" => "Ferragens")
  end

  it "fails with validation_failed for a duplicate name" do
    create(:category, organization:, name: "Ferragens")

    result = described_class.call(organization:, name: "ferragens", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Category.count).to eq(1)
  end
end

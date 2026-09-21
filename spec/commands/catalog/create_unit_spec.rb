require "rails_helper"

RSpec.describe Catalog::CreateUnit do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "creates a unit" do
    result = described_class.call(organization:, code: "SC", name: "Saco", actor:)

    expect(result).to be_success
    expect(result.value).to be_persisted
    expect(result.value.code).to eq("SC")
    expect(result.value.name).to eq("Saco")
  end

  it "records an audit event" do
    described_class.call(organization:, code: "SC", name: "Saco", actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("unit_created")
    expect(event.actor).to eq(actor)
    expect(event.field_changes).to eq("code" => "SC", "name" => "Saco")
  end

  it "fails with validation_failed for a duplicate code" do
    create(:unit, organization:, code: "SC")

    result = described_class.call(organization:, code: "SC", name: "Outro saco", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(result.details[:fields]["code"]).to include("taken")
    expect(Catalog::Unit.count).to eq(1)
  end
end

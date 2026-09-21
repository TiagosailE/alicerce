require "rails_helper"

RSpec.describe Catalog::UpdateUnit do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "updates the unit's fields" do
    unit = create(:unit, organization:, code: "SC", name: "Saco")

    result = described_class.call(unit:, attributes: { code: "SC50", name: "Saco de 50kg", active: true }, actor:)

    expect(result).to be_success
    expect(unit.reload.code).to eq("SC50")
    expect(unit.name).to eq("Saco de 50kg")
  end

  it "records only the fields that changed" do
    unit = create(:unit, organization:, code: "SC", name: "Saco")

    described_class.call(unit:, attributes: { code: "SC", name: "Saco (50kg)", active: true }, actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("unit_updated")
    expect(event.field_changes.keys).to eq([ "name" ])
    expect(event.field_changes["name"]).to eq("from" => "Saco", "to" => "Saco (50kg)")
  end

  it "does not record an audit event when nothing changed" do
    unit = create(:unit, organization:, code: "SC", name: "Saco", active: true)

    described_class.call(unit:, attributes: { code: "SC", name: "Saco", active: true }, actor:)

    expect(Audit::Event.count).to eq(0)
  end

  it "fails with validation_failed for a duplicate code" do
    create(:unit, organization:, code: "M3")
    unit = create(:unit, organization:, code: "SC")

    result = described_class.call(unit:, attributes: { code: "M3", name: unit.name, active: true }, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(unit.reload.code).to eq("SC")
  end
end

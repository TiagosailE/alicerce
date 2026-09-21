require "rails_helper"

RSpec.describe Catalog::UpdatePartner do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "updates the partner's fields" do
    partner = create(:partner, organization:, name: "Marcos Pereira")

    result = described_class.call(
      partner:, attributes: {
        name: "Marcos A. Pereira", document_type: partner.document_type, document_number: partner.document_number,
        customer: true, supplier: false, active: true
      }, actor:
    )

    expect(result).to be_success
    expect(partner.reload.name).to eq("Marcos A. Pereira")
  end

  it "can deactivate a partner" do
    partner = create(:partner, organization:)

    result = described_class.call(
      partner:, attributes: {
        name: partner.name, document_type: partner.document_type, document_number: partner.document_number,
        customer: true, supplier: false, active: false
      }, actor:
    )

    expect(result).to be_success
    expect(partner.reload.active).to be(false)
  end

  it "records an audit event with non-personal fields kept and personal fields redacted" do
    partner = create(:partner, organization:, name: "Marcos Pereira", customer: true, supplier: false)

    described_class.call(
      partner:, attributes: {
        name: "Marcos A. Pereira", document_type: partner.document_type, document_number: partner.document_number,
        customer: true, supplier: true, active: true
      }, actor:
    )

    event = Audit::Event.sole
    expect(event.action).to eq("partner_updated")
    expect(event.field_changes["name"]).to eq("changed")
    expect(event.field_changes["supplier"]).to eq("from" => false, "to" => true)
  end

  it "fails with validation_failed and changes nothing when neither customer nor supplier remains set" do
    partner = create(:partner, organization:, name: "Marcos Pereira", customer: true)

    result = described_class.call(
      partner:, attributes: {
        name: "Novo nome", document_type: partner.document_type, document_number: partner.document_number,
        customer: false, supplier: false, active: true
      }, actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(partner.reload.name).to eq("Marcos Pereira")
  end
end

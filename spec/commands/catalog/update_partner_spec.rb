require "rails_helper"

RSpec.describe Catalog::UpdatePartner do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "updates the partner's fields" do
    partner = create(:partner, organization:, name: "Marcos Pereira")

    result = described_class.call(
      partner:, revision: partner.revision, attributes: {
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
      partner:, revision: partner.revision, attributes: {
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
      partner:, revision: partner.revision, attributes: {
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
      partner:, revision: partner.revision, attributes: {
        name: "Novo nome", document_type: partner.document_type, document_number: partner.document_number,
        customer: false, supplier: false, active: true
      }, actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(partner.reload.name).to eq("Marcos Pereira")
  end

  describe "revision (ADR 0015)" do
    def attributes_for(partner, **overrides)
      { name: partner.name, document_type: partner.document_type, document_number: partner.document_number,
        customer: true, supplier: false, active: true }.merge(overrides)
    end

    it "increments the revision on an edit" do
      partner = create(:partner, organization:)

      result = described_class.call(partner:, revision: 0, attributes: attributes_for(partner, name: "Outro nome"), actor:)

      expect(result.value.revision).to eq(1)
      expect(partner.reload.revision).to eq(1)
    end

    it "leaves the revision alone when nothing changed" do
      partner = create(:partner, organization:, customer: true, supplier: false)

      described_class.call(partner:, revision: 0, attributes: attributes_for(partner), actor:)

      expect(partner.reload.revision).to eq(0)
    end

    it "answers stale, writing nothing, when the partner changed since it was read" do
      partner = create(:partner, organization:, name: "Original")
      stale_view = Catalog::Partner.find(partner.id)
      described_class.call(partner:, revision: 0, attributes: attributes_for(partner, name: "Primeira edicao"), actor:)

      result = described_class.call(
        partner: stale_view, revision: 0, attributes: attributes_for(stale_view, name: "Edicao antiga"), actor:
      )

      expect(result.error).to eq(:stale)
      expect(partner.reload.name).to eq("Primeira edicao")
    end

    it "answers validation_failed for a revision that is not an integer" do
      partner = create(:partner, organization:)

      result = described_class.call(partner:, revision: nil, attributes: attributes_for(partner), actor:)

      expect(result.error).to eq(:validation_failed)
    end
  end
end

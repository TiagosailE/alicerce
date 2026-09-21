require "rails_helper"

RSpec.describe Catalog::CreatePartner do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "creates a customer" do
    cpf = DocumentNumberGenerator.cpf

    result = described_class.call(
      organization:, name: "Marcos Pereira", document_type: "cpf", document_number: cpf, customer: true, actor:
    )

    expect(result).to be_success
    partner = result.value
    expect(partner).to be_persisted
    expect(partner.document_number).to eq(cpf)
    expect(partner.customer).to be(true)
    expect(partner.supplier).to be(false)
  end

  it "creates a supplier with contact details" do
    cnpj = DocumentNumberGenerator.cnpj

    result = described_class.call(
      organization:, name: "Cimentos Bahia Ltda", document_type: "cnpj", document_number: cnpj, supplier: true,
      email: "vendas@cimentosbahia.example", phone: "+55 71 3333-1000", actor:
    )

    expect(result).to be_success
    expect(result.value.email).to eq("vendas@cimentosbahia.example")
  end

  it "records an audit event with personal fields redacted" do
    described_class.call(
      organization:, name: "Marcos Pereira", document_type: "cpf", document_number: DocumentNumberGenerator.cpf,
      customer: true, email: "marcos@example.com", actor:
    )

    event = Audit::Event.sole
    expect(event.action).to eq("partner_created")
    expect(event.field_changes).to eq(
      "document_type" => "cpf", "customer" => true, "supplier" => false,
      "name" => "changed", "document_number" => "changed", "email" => "changed"
    )
  end

  it "fails with validation_failed and creates nothing when neither customer nor supplier is set" do
    result = described_class.call(
      organization:, name: "Marcos Pereira", document_type: "cpf", document_number: DocumentNumberGenerator.cpf, actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Partner.count).to eq(0)
    expect(Audit::Event.count).to eq(0)
  end

  it "fails with validation_failed for a document_number that fails the checksum" do
    result = described_class.call(
      organization:, name: "Marcos Pereira", document_type: "cpf", document_number: "12345678900", customer: true, actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Partner.count).to eq(0)
  end

  it "fails with validation_failed for a duplicate document_number" do
    cpf = DocumentNumberGenerator.cpf
    create(:partner, organization:, document_number: cpf)

    result = described_class.call(
      organization:, name: "Outro nome", document_type: "cpf", document_number: cpf, customer: true, actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Partner.count).to eq(1)
  end
end

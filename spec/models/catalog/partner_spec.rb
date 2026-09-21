require "rails_helper"

RSpec.describe Catalog::Partner do
  let(:organization) { create(:organization) }

  it "requires a name" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, name: "")

    expect(partner).not_to be_valid
    expect(partner.errors.of_kind?(:name, :blank)).to be(true)
  end

  it "requires document_type to be cpf or cnpj" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, document_type: "passport")

    expect(partner).not_to be_valid
    expect(partner.errors.of_kind?(:document_type, :inclusion)).to be(true)
  end

  it "rejects a document_number that fails the check-digit algorithm" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, document_type: "cpf", document_number: "12345678900")

    expect(partner).not_to be_valid
    expect(partner.errors.of_kind?(:document_number, :invalid)).to be(true)
  end

  it "rejects a CNPJ given as document_type cpf" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, document_type: "cpf", document_number: DocumentNumberGenerator.cnpj)

    expect(partner).not_to be_valid
    expect(partner.errors.of_kind?(:document_number, :invalid)).to be(true)
  end

  it "requires at least one of customer or supplier" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, customer: false, supplier: false)

    expect(partner).not_to be_valid
    expect(partner.errors.of_kind?(:base, :must_be_customer_or_supplier)).to be(true)
  end

  it "accepts a partner that is both a customer and a supplier" do
    set_current_tenant(organization)
    partner = build(:partner, organization:, customer: true, supplier: true)

    expect(partner).to be_valid
  end

  it "normalizes the document_number before saving, stripping punctuation and upcasing" do
    set_current_tenant(organization)
    cnpj = DocumentNumberGenerator.cnpj
    formatted = cnpj.sub(/\A(.{2})(.{3})(.{3})(.{4})(\d{2})\z/, '\1.\2.\3/\4-\5').downcase
    partner = create(:partner, :supplier, organization:, document_number: formatted)

    expect(partner.document_number).to eq(cnpj)
  end

  it "rejects a duplicate document_number within the same organization" do
    set_current_tenant(organization)
    cpf = DocumentNumberGenerator.cpf
    create(:partner, organization:, document_number: cpf)
    duplicate = build(:partner, organization:, document_number: cpf)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:document_number, :taken)).to be(true)
  end

  it "encrypts document_number at rest" do
    set_current_tenant(organization)
    cpf = DocumentNumberGenerator.cpf
    partner = create(:partner, organization:, document_number: cpf)

    raw = ActiveRecord::Base.connection.select_value("SELECT document_number FROM catalog_partners WHERE id = #{partner.id}")

    expect(raw).not_to eq(cpf)
    expect(partner.reload.document_number).to eq(cpf)
  end
end

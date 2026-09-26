require "rails_helper"

RSpec.describe Catalog::UpdateProduct do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:unidade) { create(:unit, organization:, code: "UN") }
  let(:milheiro) { create(:unit, organization:, code: "MIL") }

  before { set_current_tenant(organization) }

  def create_product
    product = create(:product, organization:, sku: "TIJ-001", name: "Tijolo comum", stock_unit: unidade)
    create(:unit_conversion, organization:, product:, purchase_unit: milheiro, factor: "1000")
    product
  end

  it "updates the product's own fields" do
    product = create_product

    result = described_class.call(
      product:, revision: product.revision, attributes: { sku: "TIJ-001", name: "Tijolo comum 8 furos", stock_unit_id: unidade.id, active: true },
      actor:
    )

    expect(result).to be_success
    expect(product.reload.name).to eq("Tijolo comum 8 furos")
  end

  it "updates the unit conversion when conversion_attributes are given" do
    product = create_product
    saco = create(:unit, organization:, code: "SC")

    result = described_class.call(
      product:, revision: product.revision, attributes: { sku: product.sku, name: product.name, stock_unit_id: unidade.id, active: true },
      conversion_attributes: { purchase_unit_id: saco.id, factor: "50" },
      actor:
    )

    expect(result).to be_success
    conversion = product.unit_conversion.reload
    expect(conversion.purchase_unit).to eq(saco)
    expect(conversion.factor).to eq(BigDecimal("50"))
  end

  it "records the unit conversion change under its own key" do
    product = create_product

    described_class.call(
      product:, revision: product.revision, attributes: { sku: product.sku, name: product.name, stock_unit_id: unidade.id, active: true },
      conversion_attributes: { purchase_unit_id: milheiro.id, factor: "1100" },
      actor:
    )

    event = Audit::Event.sole
    expect(event.field_changes["unit_conversion.factor"]).to eq("from" => "1000.0", "to" => "1100.0")
  end

  it "fails with validation_failed and changes nothing when the factor turns non-positive" do
    product = create_product

    result = described_class.call(
      product:, revision: product.revision, attributes: { sku: product.sku, name: "Novo nome", stock_unit_id: unidade.id, active: true },
      conversion_attributes: { purchase_unit_id: milheiro.id, factor: "-1" },
      actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(product.reload.name).to eq("Tijolo comum")
  end

  describe "revision (ADR 0015)" do
    def attributes_for(product, **overrides)
      { sku: product.sku, name: product.name, stock_unit_id: product.stock_unit_id, active: true }.merge(overrides)
    end

    it "increments the revision on an edit" do
      product = create_product

      result = described_class.call(product:, revision: 0, attributes: attributes_for(product, name: "Outro"), actor:)

      expect(result).to be_success
      expect(result.value.revision).to eq(1)
      expect(product.reload.revision).to eq(1)
    end

    it "increments the revision when only the conversion changed" do
      product = create_product

      described_class.call(
        product:, revision: 0, attributes: attributes_for(product),
        conversion_attributes: { purchase_unit_id: milheiro.id, factor: "1100" }, actor:
      )

      expect(product.reload.revision).to eq(1)
    end

    it "leaves the revision and the audit trail alone when nothing changed" do
      product = create_product

      result = described_class.call(product:, revision: 0, attributes: attributes_for(product), actor:)

      expect(result).to be_success
      expect(product.reload.revision).to eq(0)
      expect(Audit::Event.count).to eq(0)
    end

    it "answers stale, writing nothing, for a revision that is no longer current" do
      product = create_product
      described_class.call(product:, revision: 0, attributes: attributes_for(product, name: "Primeira edicao"), actor:)
      stale_view = Catalog::Product.find(product.id)

      result = described_class.call(
        product: stale_view, revision: 0, attributes: attributes_for(stale_view, name: "Edicao antiga"),
        conversion_attributes: { purchase_unit_id: milheiro.id, factor: "1" }, actor:
      )

      expect(result).not_to be_success
      expect(result.error).to eq(:stale)
      expect(result.details[:current_revision]).to eq(1)
      expect(product.reload.name).to eq("Primeira edicao")
      expect(product.unit_conversion.reload.factor).to eq(BigDecimal("1000"))
    end

    it "does not let a name edit revert a factor edit made in between" do
      product = create_product
      other_admin_view = Catalog::Product.find(product.id)
      described_class.call(
        product:, revision: 0, attributes: attributes_for(product),
        conversion_attributes: { purchase_unit_id: milheiro.id, factor: "50" }, actor:
      )

      result = described_class.call(
        product: other_admin_view, revision: 0, attributes: attributes_for(other_admin_view, name: "So o nome"),
        conversion_attributes: { purchase_unit_id: milheiro.id, factor: "1000" }, actor:
      )

      expect(result.error).to eq(:stale)
      expect(product.unit_conversion.reload.factor).to eq(BigDecimal("50"))
    end

    it "answers validation_failed for a revision that is not an integer" do
      product = create_product

      result = described_class.call(product:, revision: nil, attributes: attributes_for(product), actor:)

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq("revision" => [ "not_a_number" ])
    end
  end

  describe "stock unit" do
    it "cannot change, because every quantity is stored in it" do
      product = create_product

      result = described_class.call(
        product:, revision: 0, attributes: { sku: product.sku, name: product.name, stock_unit_id: milheiro.id, active: true }, actor:
      )

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]["stock_unit"]).to eq([ "immutable" ])
      expect(product.reload.stock_unit).to eq(unidade)
    end
  end
end

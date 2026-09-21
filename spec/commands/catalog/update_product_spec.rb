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
      product:, attributes: { sku: "TIJ-001", name: "Tijolo comum 8 furos", stock_unit_id: unidade.id, active: true },
      actor:
    )

    expect(result).to be_success
    expect(product.reload.name).to eq("Tijolo comum 8 furos")
  end

  it "updates the unit conversion when conversion_attributes are given" do
    product = create_product
    saco = create(:unit, organization:, code: "SC")

    result = described_class.call(
      product:, attributes: { sku: product.sku, name: product.name, stock_unit_id: unidade.id, active: true },
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
      product:, attributes: { sku: product.sku, name: product.name, stock_unit_id: unidade.id, active: true },
      conversion_attributes: { purchase_unit_id: milheiro.id, factor: "1100" },
      actor:
    )

    event = Audit::Event.sole
    expect(event.field_changes["unit_conversion.factor"]).to eq("from" => "1000.0", "to" => "1100.0")
  end

  it "fails with validation_failed and changes nothing when the factor turns non-positive" do
    product = create_product

    result = described_class.call(
      product:, attributes: { sku: product.sku, name: "Novo nome", stock_unit_id: unidade.id, active: true },
      conversion_attributes: { purchase_unit_id: milheiro.id, factor: "-1" },
      actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(product.reload.name).to eq("Tijolo comum")
  end
end

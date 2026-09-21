require "rails_helper"

RSpec.describe Catalog::CreateProduct do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:unidade) { create(:unit, organization:, code: "UN") }
  let(:milheiro) { create(:unit, organization:, code: "MIL") }

  before { set_current_tenant(organization) }

  it "creates a product with its unit conversion" do
    result = described_class.call(
      organization:, sku: "TIJ-001", name: "Tijolo comum",
      stock_unit_id: unidade.id, purchase_unit_id: milheiro.id, factor: "1000",
      actor:
    )

    expect(result).to be_success
    product = result.value
    expect(product).to be_persisted
    expect(product.stock_unit).to eq(unidade)
    expect(product.unit_conversion.purchase_unit).to eq(milheiro)
    expect(product.unit_conversion.factor).to eq(BigDecimal("1000"))
  end

  it "accepts an optional category" do
    category = create(:category, organization:)

    result = described_class.call(
      organization:, sku: "TIJ-001", name: "Tijolo comum", category_id: category.id,
      stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1",
      actor:
    )

    expect(result).to be_success
    expect(result.value.category).to eq(category)
  end

  it "records an audit event" do
    described_class.call(
      organization:, sku: "TIJ-001", name: "Tijolo comum",
      stock_unit_id: unidade.id, purchase_unit_id: milheiro.id, factor: "1000",
      actor:
    )

    event = Audit::Event.sole
    expect(event.action).to eq("product_created")
    expect(event.field_changes).to eq("sku" => "TIJ-001", "name" => "Tijolo comum")
  end

  it "fails with validation_failed and creates neither row when the factor is not positive" do
    result = described_class.call(
      organization:, sku: "TIJ-001", name: "Tijolo comum",
      stock_unit_id: unidade.id, purchase_unit_id: milheiro.id, factor: "0",
      actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Product.count).to eq(0)
    expect(Catalog::UnitConversion.count).to eq(0)
  end

  it "fails with validation_failed for a duplicate sku" do
    create(:product, organization:, sku: "TIJ-001", stock_unit: unidade)

    result = described_class.call(
      organization:, sku: "TIJ-001", name: "Outro tijolo",
      stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1",
      actor:
    )

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(Catalog::Product.count).to eq(1)
  end
end

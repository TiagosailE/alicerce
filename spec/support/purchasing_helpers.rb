# Building blocks for the purchasing specs: a supplier and products that can
# actually be ordered (a product needs its purchase unit conversion).
module PurchasingHelpers
  # A product ordered in `purchase_unit_code` and stocked in units, `factor`
  # stock units to a purchase unit.
  def orderable_product(organization, sku:, name: "Produto #{sku}", purchase_unit_code: "SC", factor: "1")
    stock_unit = Catalog::Unit.find_by(code: "UN") || create(:unit, organization:, code: "UN", name: "Unidade")
    purchase_unit = Catalog::Unit.find_by(code: purchase_unit_code) || create(:unit, organization:, code: purchase_unit_code, name: purchase_unit_code)
    product = create(:product, organization:, sku:, name:, stock_unit:)
    create(:unit_conversion, organization:, product:, purchase_unit:, factor:)
    product
  end

  def supplier_for(organization, **attributes)
    create(:partner, organization:, customer: false, supplier: true, **attributes)
  end

  def line_input(product, quantity: "10", unit_price_cents: 1_000, discount_bp: 0)
    { product_id: product.id, quantity:, unit_price_cents:, discount_bp: }
  end

  def create_order!(organization:, supplier:, actor:, lines:, **options)
    result = Purchasing::CreateOrder.call(organization:, actor:, supplier:, lines:, **options)
    raise "could not create the order: #{result.details}" unless result.success?

    result.value
  end
end

RSpec.configure { |config| config.include PurchasingHelpers }

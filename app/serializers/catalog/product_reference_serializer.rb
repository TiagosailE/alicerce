module Catalog
  # A product as another resource refers to it (a balance, a movement): enough
  # to recognize it and to read its quantities in the right unit.
  class ProductReferenceSerializer
    def initialize(product)
      @product = product
    end

    def as_json
      { id: @product.id, sku: @product.sku, name: @product.name, stock_unit: UnitSerializer.new(@product.stock_unit).as_json }
    end
  end
end

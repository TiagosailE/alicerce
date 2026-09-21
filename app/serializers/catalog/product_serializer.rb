module Catalog
  class ProductSerializer
    def initialize(product)
      @product = product
    end

    def as_json
      {
        id: @product.id,
        sku: @product.sku,
        name: @product.name,
        active: @product.active,
        category: @product.category && CategorySerializer.new(@product.category).as_json,
        stock_unit: UnitSerializer.new(@product.stock_unit).as_json,
        unit_conversion: @product.unit_conversion && UnitConversionSerializer.new(@product.unit_conversion).as_json
      }
    end
  end
end

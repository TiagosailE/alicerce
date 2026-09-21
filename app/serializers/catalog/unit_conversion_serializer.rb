module Catalog
  class UnitConversionSerializer
    def initialize(unit_conversion)
      @unit_conversion = unit_conversion
    end

    def as_json
      {
        purchase_unit: UnitSerializer.new(@unit_conversion.purchase_unit).as_json,
        factor: @unit_conversion.factor.to_s("F")
      }
    end
  end
end

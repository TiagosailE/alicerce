module Catalog
  class UnitConversionSerializer
    def initialize(unit_conversion)
      @unit_conversion = unit_conversion
    end

    def as_json
      {
        purchase_unit: UnitSerializer.new(@unit_conversion.purchase_unit).as_json,
        factor: DecimalString.format(@unit_conversion.factor, UnitConversion::DECIMAL_PLACES)
      }
    end
  end
end

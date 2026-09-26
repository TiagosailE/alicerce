module Catalog
  class UnitConversionSerializer
    def initialize(unit_conversion)
      @unit_conversion = unit_conversion
    end

    def as_json
      {
        purchase_unit: UnitSerializer.new(@unit_conversion.purchase_unit).as_json,
        factor: fixed_scale(@unit_conversion.factor)
      }
    end

    private
      # A decimal string always carries every place the column has, so
      # "1000.000000" and never "1000.0" (ADR 0006, the OpenAPI pattern).
      def fixed_scale(value)
        whole, fraction = value.round(UnitConversion::DECIMAL_PLACES).to_s("F").split(".")
        "#{whole}.#{fraction.to_s.ljust(UnitConversion::DECIMAL_PLACES, "0")}"
      end
  end
end

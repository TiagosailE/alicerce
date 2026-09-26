module Catalog
  # The factor that converts one purchase unit into stock units for a
  # product (ADR 0006: numeric(15,6), rounded half up wherever it is
  # applied). One row per product: buying by the purchase_unit and stocking
  # by the product's stock_unit always uses the same factor.
  class UnitConversion < ApplicationRecord
    include TenantScoped
    include RaceSafeUniqueness

    belongs_to :product, class_name: "Catalog::Product", inverse_of: :unit_conversion
    belongs_to :purchase_unit, class_name: "Catalog::Unit"

    # numeric(15,6) holds nine integer digits and six decimals. Anything the
    # column cannot store exactly is a validation error: never a silent
    # rounding (ADR 0006) and never a database range error surfacing as 500.
    MAX_FACTOR = 1_000_000_000
    DECIMAL_PLACES = 6

    validates :factor, presence: true, numericality: { greater_than: 0, less_than: MAX_FACTOR }
    validate :factor_fits_the_column_scale
    validates :product_id, uniqueness: true

    private
      # The attribute is already cast (and rounded) by the time a validator
      # reads it, so the check has to look at what the client actually sent.
      def factor_fits_the_column_scale
        sent = BigDecimal(factor_before_type_cast.to_s, exception: false)
        errors.add(:factor, :too_many_decimals) if sent && sent != sent.round(DECIMAL_PLACES)
      end
  end
end

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

    validates :factor, presence: true, numericality: { greater_than: 0 }
    validates :product_id, uniqueness: true
  end
end

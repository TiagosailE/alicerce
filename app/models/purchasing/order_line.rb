module Purchasing
  # One product on an order (ADR 0017). Its amounts are worked out and stored
  # when it is saved, by the named rounding points of ADR 0006, so nothing
  # downstream (a receipt, a screen) computes money from a quantity and a price.
  class OrderLine < ApplicationRecord
    include TenantScoped

    QUANTITY_PLACES = 3
    QUANTITY_INTEGER_DIGITS = 12

    belongs_to :order, class_name: "Purchasing::Order", inverse_of: :lines
    belongs_to :product, class_name: "Catalog::Product"
    belongs_to :purchase_unit, class_name: "Catalog::Unit"

    before_validation :calculate_amounts

    validates :quantity, numericality: { greater_than: 0, less_than: 10**QUANTITY_INTEGER_DIGITS }
    validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :discount_bp, numericality: { only_integer: true, in: 0..10_000 }
    validate :quantity_fits_the_column_scale
    validate :gross_fits_the_cap

    # What the buyer would still receive on this line.
    def remaining_quantity = quantity - received_quantity

    # The product's name, sku, purchase unit and factor as they are now. Called
    # when a draft line is saved and again at approval, which freezes them.
    def copy_from(product)
      conversion = product.unit_conversion
      self.product = product
      self.product_sku = product.sku
      self.product_name = product.name
      self.stock_unit_code = product.stock_unit.code
      return unless conversion

      self.purchase_unit = conversion.purchase_unit
      self.purchase_unit_code = conversion.purchase_unit.code
      self.factor = conversion.factor
    end

    private
      # gross = quantity x price, discount = gross x basis points, net = gross
      # minus discount; each division rounds half up (ADR 0017).
      def calculate_amounts
        # A value the validations are about to refuse has no amounts to work out.
        return if quantity.blank? || unit_price_cents.blank? || discount_bp.blank?
        return unless quantity.positive? && unit_price_cents >= 0 && discount_bp.between?(0, 10_000)

        self.gross_cents = Inventory::Costing.value_at_unit_cost(quantity, unit_price_cents)
        self.discount_cents = Inventory::Costing.round_half_up(Rational(gross_cents * discount_bp, 10_000))
        self.net_cents = gross_cents - discount_cents
      end

      def quantity_fits_the_column_scale
        sent = BigDecimal(quantity_before_type_cast.to_s, exception: false)
        errors.add(:quantity, :too_many_decimals) if sent && sent != sent.round(QUANTITY_PLACES)
      end

      def gross_fits_the_cap
        errors.add(:quantity, :too_large) if gross_cents.to_i > Inventory::Ledger::VALUE_CAP_CENTS
      end
  end
end

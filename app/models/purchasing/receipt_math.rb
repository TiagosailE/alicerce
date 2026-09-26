module Purchasing
  # What a receipt of `quantity` purchase units takes from an order line
  # (ADR 0017). Every figure is the difference of a cumulative one, rounded half
  # up on exact rationals, so:
  #
  # - each cumulative figure is monotone in the quantity, hence no amount is ever
  #   negative and a discount never exceeds its gross;
  # - when the last receipt brings the received quantity to the line's quantity,
  #   the sums equal the line's own gross, discount and stock quantity exactly,
  #   with no special case for "the receipt that completes the line" (ADR 0006's
  #   completion rule, applied to a discount that is itself a rounded share of a
  #   rounded gross, can make the last discount negative).
  #
  # Nothing is written here: the caller holds the line's lock and decides.
  module ReceiptMath
    STOCK_PLACES = 3

    Amounts = Data.define(:gross_cents, :discount_cents, :net_cents, :stock_quantity)

    module_function

    def call(line:, quantity:)
      cumulative = line.received_quantity + quantity
      gross_cumulative = Inventory::Costing.value_at_unit_cost(cumulative, line.unit_price_cents)
      discount_cumulative = Inventory::Costing.round_half_up(Rational(gross_cumulative * line.discount_bp, 10_000))
      gross = gross_cumulative - line.received_gross_cents
      discount = discount_cumulative - line.received_discount_cents

      Amounts.new(
        gross_cents: gross, discount_cents: discount, net_cents: gross - discount,
        stock_quantity: stock_quantity(cumulative, line.factor) - line.received_stock_quantity
      )
    end

    # The stock units a cumulative quantity of purchase units comes to: a named
    # rounding point (unit conversion, to three places).
    def stock_quantity(purchase_quantity, factor)
      scaled = Inventory::Costing.round_half_up(purchase_quantity.to_r * factor.to_r * 10**STOCK_PLACES)
      BigDecimal(scaled.to_s) / 10**STOCK_PLACES
    end
  end
end

module Inventory
  # The rounding points of ADR 0006 that stock touches, all half up and all
  # exact: quantities and costs are BigDecimal, converted to Rational so a
  # division never loses a digit, and only the final integer number of cents is
  # rounded. No Float anywhere.
  module Costing
    module_function

    # Half up on a non-negative rational: 2.5 becomes 3, 2.4999 becomes 2.
    def round_half_up(rational)
      raise ArgumentError, "round_half_up takes a non-negative value" if rational.negative?

      (rational + Rational(1, 2)).floor
    end

    # What a quantity of stock is worth at a unit cost given in cents, which
    # may be a fraction of a cent (bricks at R$ 849,90 per thousand are 84.99
    # cents each). A named rounding point: line totals.
    def value_at_unit_cost(quantity, unit_cost)
      round_half_up(quantity.to_r * unit_cost.to_r)
    end

    # What `quantity` units are worth out of a balance of `on_hand` units worth
    # `value_cents`, at that balance's average cost. A named rounding point:
    # issue costs. The caller handles the movement that empties the balance,
    # which takes all the remaining value rather than a rounded share.
    def value_at_average_cost(value_cents, quantity, on_hand)
      round_half_up(Rational(value_cents) * quantity.to_r / on_hand.to_r)
    end
  end
end

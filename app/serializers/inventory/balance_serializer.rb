module Inventory
  # value_visible is false for a role that may read quantities but not what the
  # stock is worth or cost (Identity::Capabilities.view_stock_value?); those
  # two fields are then null rather than absent, so the shape never varies.
  class BalanceSerializer
    def initialize(balance, value_visible:)
      @balance = balance
      @value_visible = value_visible
    end

    def as_json
      {
        id: @balance.id,
        product: Catalog::ProductReferenceSerializer.new(@balance.product).as_json,
        warehouse: WarehouseSerializer.new(@balance.warehouse).as_json,
        on_hand: quantity(@balance.on_hand),
        reserved: quantity(@balance.reserved),
        available: quantity(@balance.available),
        value_cents: (@balance.value_cents if @value_visible),
        currency: @balance.currency,
        last_unit_cost_cents: (DecimalString.format(@balance.last_unit_cost, 6) if @value_visible)
      }
    end

    private
      def quantity(value) = DecimalString.format(value, 3)
  end
end

module Inventory
  class BalanceSerializer
    def initialize(balance)
      @balance = balance
    end

    def as_json
      {
        id: @balance.id,
        product: Catalog::ProductReferenceSerializer.new(@balance.product).as_json,
        warehouse: WarehouseSerializer.new(@balance.warehouse).as_json,
        on_hand: quantity(@balance.on_hand),
        reserved: quantity(@balance.reserved),
        available: quantity(@balance.available),
        value_cents: @balance.value_cents,
        currency: @balance.currency,
        last_unit_cost: DecimalString.format(@balance.last_unit_cost, 6)
      }
    end

    private
      def quantity(value) = DecimalString.format(value, 3)
  end
end

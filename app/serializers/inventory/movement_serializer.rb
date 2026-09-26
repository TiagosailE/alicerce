module Inventory
  # See BalanceSerializer for value_visible.
  class MovementSerializer
    def initialize(movement, value_visible:)
      @movement = movement
      @value_visible = value_visible
    end

    def as_json
      {
        id: @movement.id,
        kind: @movement.kind,
        reason: @movement.reason,
        note: @movement.note,
        product: Catalog::ProductReferenceSerializer.new(@movement.product).as_json,
        warehouse: WarehouseSerializer.new(@movement.warehouse).as_json,
        quantity: DecimalString.format(@movement.quantity, 3),
        value_cents: (@movement.value_cents if @value_visible),
        currency: @movement.currency,
        on_hand_after: DecimalString.format(@movement.on_hand_after, 3),
        value_after_cents: (@movement.value_after_cents if @value_visible),
        actor: { id: @movement.actor_user.id, name: @movement.actor_user.name },
        created_at: @movement.created_at.utc.iso8601
      }
    end
  end
end

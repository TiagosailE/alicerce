module Inventory
  class MovementSerializer
    def initialize(movement)
      @movement = movement
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
        value_cents: @movement.value_cents,
        currency: @movement.currency,
        on_hand_after: DecimalString.format(@movement.on_hand_after, 3),
        value_after_cents: @movement.value_after_cents,
        actor: { id: @movement.actor_user.id, name: @movement.actor_user.name },
        created_at: @movement.created_at.utc.iso8601
      }
    end
  end
end

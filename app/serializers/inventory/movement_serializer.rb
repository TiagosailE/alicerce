module Inventory
  # Only whoever may read the ledger (Identity::Capabilities.view_stock_movements?)
  # ever gets to serialize a movement, and they see values, notes and actors in full.
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
        receipt: receipt,
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

    private
      # The receipt a receipt movement came from, so the ledger can point at it.
      def receipt
        receipt = @movement.receipt_line&.receipt
        receipt && { id: receipt.id, number: receipt.number }
      end
  end
end

module Purchasing
  # The list shape: enough to recognize an order and know where it stands.
  class OrderSummarySerializer
    def initialize(order)
      @order = order
    end

    def as_json
      {
        id: @order.id,
        number: @order.number,
        status: @order.status,
        supplier: { id: @order.supplier_id, name: @order.supplier_name },
        total_cents: @order.total_cents,
        currency: @order.currency,
        created_at: @order.created_at.utc.iso8601
      }
    end
  end
end

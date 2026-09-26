module Purchasing
  # The list shape: enough to recognize a receipt and know what it came to.
  class ReceiptSummarySerializer
    def initialize(receipt)
      @receipt = receipt
    end

    def as_json
      order = @receipt.order
      {
        id: @receipt.id,
        number: @receipt.number,
        order: { id: order.id, number: order.number },
        supplier: { id: order.supplier_id, name: order.supplier_name },
        warehouse: { id: @receipt.warehouse_id, name: @receipt.warehouse.name },
        received_on: @receipt.received_on.iso8601,
        total_cents: @receipt.total_cents,
        currency: @receipt.currency,
        created_at: @receipt.created_at.utc.iso8601
      }
    end
  end
end

module Purchasing
  # The detail shape. The supplier's CPF, copied onto the order, is masked for a
  # role that may not see a partner's in full (ADR 0014); personal_data_visible
  # says which it is.
  class OrderSerializer
    def initialize(order, personal_data_visible:)
      @order = order
      @personal_data_visible = personal_data_visible
    end

    def as_json
      {
        id: @order.id,
        number: @order.number,
        status: @order.status,
        supplier: supplier,
        installments: @order.installments,
        first_due_days: @order.first_due_days,
        interval_days: @order.interval_days,
        note: @order.note,
        total_cents: @order.total_cents,
        currency: @order.currency,
        revision: @order.revision,
        personal_data_visible: @personal_data_visible,
        approved_at: @order.approved_at&.utc&.iso8601,
        cancelled_at: @order.cancelled_at&.utc&.iso8601,
        created_at: @order.created_at.utc.iso8601,
        lines: @order.lines.map { |line| line_json(line) }
      }
    end

    private
      def supplier
        number = @order.supplier_document_number
        number = Catalog::DocumentNumber.mask(@order.supplier_document_type, number) unless @personal_data_visible
        { id: @order.supplier_id, name: @order.supplier_name, document_type: @order.supplier_document_type, document_number: number }
      end

      def line_json(line)
        {
          id: line.id,
          position: line.position,
          product: { id: line.product_id, sku: line.product_sku, name: line.product_name },
          purchase_unit_code: line.purchase_unit_code,
          stock_unit_code: line.stock_unit_code,
          factor: DecimalString.format(line.factor, 6),
          quantity: DecimalString.format(line.quantity, 3),
          received_quantity: DecimalString.format(line.received_quantity, 3),
          remaining_quantity: DecimalString.format(line.remaining_quantity, 3),
          unit_price_cents: line.unit_price_cents,
          discount_bp: line.discount_bp,
          gross_cents: line.gross_cents,
          discount_cents: line.discount_cents,
          net_cents: line.net_cents
        }
      end
  end
end

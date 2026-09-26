module Purchasing
  # The receipt as a report (ADR 0017): per line what was priced, what it came
  # to and what entered stock, all stored, so no screen sums or rounds anything.
  # The payable it opened is included only for a role that reads payables.
  class ReceiptSerializer
    def initialize(receipt, payable_visible:)
      @receipt = receipt
      @payable_visible = payable_visible
    end

    def as_json
      summary.merge(
        status: @receipt.status,
        supplier_invoice_number: @receipt.supplier_invoice_number,
        created_by: { id: @receipt.created_by_user_id, name: @receipt.created_by_user.name },
        lines: @receipt.lines.map { |line| line_json(line) },
        payable: payable
      )
    end

    private
      def summary = Purchasing::ReceiptSummarySerializer.new(@receipt).as_json

      def payable
        title = @receipt.title
        return unless @payable_visible && title

        Finance::TitleSerializer.new(title).as_json
      end

      def line_json(line)
        {
          id: line.id,
          order_line_id: line.order_line_id,
          product: { id: line.product_id, sku: line.product_sku, name: line.product_name },
          purchase_unit_code: line.purchase_unit_code,
          stock_unit_code: line.stock_unit_code,
          factor: DecimalString.format(line.factor, 6),
          unit_price_cents: line.unit_price_cents,
          discount_bp: line.discount_bp,
          quantity: DecimalString.format(line.quantity, 3),
          stock_quantity: DecimalString.format(line.stock_quantity, 3),
          gross_cents: line.gross_cents,
          discount_cents: line.discount_cents,
          net_cents: line.net_cents
        }
      end
  end
end

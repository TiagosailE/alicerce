module Purchasing
  # Receipts, newest number first. q matches the number or the supplier's name
  # as copied onto the order.
  class ReceiptsQuery
    include Pagination

    def results
      paginated(@scope.includes(:warehouse, order: []).order(number: :desc))
    end

    private
      def filtered(scope, order_id: nil, warehouse_id: nil, q: nil)
        scope = scope.where(order_id:) if order_id.present?
        scope = scope.where(warehouse_id:) if warehouse_id.present?
        if q.present?
          pattern = "%#{sanitize_like(q)}%"
          scope = scope.joins(:order).where(
            "purchasing_orders.supplier_name ILIKE :q OR CAST(purchasing_receipts.number AS text) LIKE :q", q: pattern
          )
        end
        scope
      end
  end
end

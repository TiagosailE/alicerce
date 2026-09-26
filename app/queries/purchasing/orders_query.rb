module Purchasing
  # Purchase orders, newest number first. q matches the number or the supplier's
  # name as copied onto the order.
  class OrdersQuery
    include Pagination

    def results
      paginated(@scope.order(number: :desc))
    end

    private
      def filtered(scope, status: nil, supplier_id: nil, q: nil)
        scope = scope.where(status:) if status.present?
        scope = scope.where(supplier_id:) if supplier_id.present?
        if q.present?
          pattern = "%#{sanitize_like(q)}%"
          scope = scope.where("purchasing_orders.supplier_name ILIKE :q OR CAST(purchasing_orders.number AS text) LIKE :q", q: pattern)
        end
        scope
      end
  end
end

module Inventory
  # The ledger, newest first.
  class MovementsQuery
    include Pagination

    def results
      paginated(@scope.includes(:actor_user, :warehouse, product: :stock_unit).order(id: :desc))
    end

    private
      def filtered(scope, warehouse_id: nil, product_id: nil, reason: nil)
        scope = scope.where(warehouse_id:) if warehouse_id.present?
        scope = scope.where(product_id:) if product_id.present?
        scope = scope.where(reason:) if reason.present?
        scope
      end
  end
end

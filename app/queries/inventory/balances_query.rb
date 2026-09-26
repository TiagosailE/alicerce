module Inventory
  # The stock position: one row per product and warehouse that has ever held
  # stock, by product name. q searches the product's name and sku.
  class BalancesQuery
    include Pagination

    def results
      paginated(@scope.includes(:warehouse, product: :stock_unit).joins(:product, :warehouse)
        .order("catalog_products.name", "inventory_warehouses.name", :id))
    end

    private
      def filtered(scope, warehouse_id: nil, product_id: nil, q: nil)
        scope = scope.where(warehouse_id:) if warehouse_id.present?
        scope = scope.where(product_id:) if product_id.present?
        scope = scope.joins(:product).where("catalog_products.name ILIKE :q OR catalog_products.sku ILIKE :q", q: "%#{sanitize_like(q)}%") if q.present?
        scope
      end
  end
end

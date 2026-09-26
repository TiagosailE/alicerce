module Catalog
  # The first list that needs filters (backend-conventions skill): active
  # state, category and a name/sku search.
  class ProductsQuery
    include Pagination

    def results
      paginated(@scope.includes(:category, :stock_unit, unit_conversion: :purchase_unit).order(:name, :id))
    end

    private
      def filtered(scope, category_id: nil, active: nil, q: nil)
        scope = scope.where(category_id:) if category_id.present?
        scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(active)) if active.present?
        scope = scope.where("name ILIKE :q OR sku ILIKE :q", q: "%#{sanitize_like(q)}%") if q.present?
        scope
      end
  end
end

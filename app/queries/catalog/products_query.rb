module Catalog
  # The first list that needs filters (backend-conventions skill): active
  # state, category and a name/sku search. Pagination's own #initialize is
  # replaced, not extended, since it is defined directly on this class by
  # Pagination's `included do` block, not on an ancestor module; @scope
  # must already be the filtered relation here so Pagination#meta counts
  # the filtered total, not the whole table.
  class ProductsQuery
    include Pagination

    def initialize(scope, page: nil, per_page: nil, category_id: nil, active: nil, q: nil)
      @page = [ page.to_i, 1 ].max
      @per_page = per_page.presence ? per_page.to_i.clamp(1, Pagination::MAX_PER_PAGE) : Pagination::DEFAULT_PER_PAGE
      @scope = filtered(scope, category_id:, active:, q:)
    end

    def results
      paginated(@scope.includes(:category, :stock_unit, unit_conversion: :purchase_unit).order(:name, :id))
    end

    private
      def filtered(scope, category_id:, active:, q:)
        scope = scope.where(category_id:) if category_id.present?
        scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(active)) if active.present?
        scope = scope.where("name ILIKE :q OR sku ILIKE :q", q: "%#{sanitize_like(q)}%") if q.present?
        scope
      end

      def sanitize_like(value)
        value.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }
      end
  end
end

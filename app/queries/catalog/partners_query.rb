module Catalog
  # document_number is encrypted (ADR 0012): only an exact match on the
  # decrypted value would work, and nothing needs that yet, so q searches
  # name only, the same restriction PartnersQuery accepts until a screen
  # needs document lookup.
  class PartnersQuery
    include Pagination

    def initialize(scope, page: nil, per_page: nil, customer: nil, supplier: nil, active: nil, q: nil)
      @page = [ page.to_i, 1 ].max
      @per_page = per_page.presence ? per_page.to_i.clamp(1, Pagination::MAX_PER_PAGE) : Pagination::DEFAULT_PER_PAGE
      @scope = filtered(scope, customer:, supplier:, active:, q:)
    end

    def results
      paginated(@scope.order(:name, :id))
    end

    private
      def filtered(scope, customer:, supplier:, active:, q:)
        scope = scope.where(customer: ActiveModel::Type::Boolean.new.cast(customer)) if customer.present?
        scope = scope.where(supplier: ActiveModel::Type::Boolean.new.cast(supplier)) if supplier.present?
        scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(active)) if active.present?
        scope = scope.where("name ILIKE :q", q: "%#{sanitize_like(q)}%") if q.present?
        scope
      end

      def sanitize_like(value)
        value.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }
      end
  end
end

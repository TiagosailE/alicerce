module Audit
  # Pagination for the audit list endpoint (CONTRIBUTING.md: page, per_page,
  # default 25, max 100).
  class EventsQuery
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE = 100

    def initialize(scope, page: nil, per_page: nil)
      @scope = scope
      @page = [ page.to_i, 1 ].max
      @per_page = per_page.presence ? per_page.to_i.clamp(1, MAX_PER_PAGE) : DEFAULT_PER_PAGE
    end

    def results
      @scope.order(created_at: :desc, id: :desc).offset((@page - 1) * @per_page).limit(@per_page)
    end

    def meta
      { page: @page, per_page: @per_page, total: @scope.count }
    end
  end
end

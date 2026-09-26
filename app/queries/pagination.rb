# Shared plumbing for every list query (backend-conventions skill): page and
# per_page clamping (default 25, max 100), the meta block, an overridable
# `filtered` hook so a query with filters counts the filtered total, and
# escaping for LIKE searches.
module Pagination
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100
  # An OFFSET past bigint is a database error, and no list has this many pages.
  MAX_PAGE = 1_000_000

  def initialize(scope, page: nil, per_page: nil, **filters)
    @page = page.to_i.clamp(1, MAX_PAGE)
    @per_page = per_page.presence ? per_page.to_i.clamp(1, MAX_PER_PAGE) : DEFAULT_PER_PAGE
    @scope = filtered(scope, **filters)
  end

  def meta
    { page: @page, per_page: @per_page, total: @scope.count }
  end

  private
    def filtered(scope, **) = scope

    def paginated(ordered_scope)
      ordered_scope.offset((@page - 1) * @per_page).limit(@per_page)
    end

    def sanitize_like(value)
      value.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }
    end
end

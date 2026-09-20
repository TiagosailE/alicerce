# Shared page/per_page clamping and meta for every list query
# (backend-conventions skill: page, per_page, default 25, max 100).
module Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  included do
    def initialize(scope, page: nil, per_page: nil)
      @scope = scope
      @page = [ page.to_i, 1 ].max
      @per_page = per_page.presence ? per_page.to_i.clamp(1, MAX_PER_PAGE) : DEFAULT_PER_PAGE
    end

    def meta
      { page: @page, per_page: @per_page, total: @scope.count }
    end
  end

  private
    def paginated(ordered_scope)
      ordered_scope.offset((@page - 1) * @per_page).limit(@per_page)
    end
end

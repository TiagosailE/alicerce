module Audit
  class EventsQuery
    include Pagination

    def results
      paginated(@scope.order(created_at: :desc, id: :desc))
    end
  end
end

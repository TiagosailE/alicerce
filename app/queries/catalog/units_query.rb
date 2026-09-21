module Catalog
  class UnitsQuery
    include Pagination

    def results
      paginated(@scope.order(:code, :id))
    end
  end
end

module Catalog
  class CategoriesQuery
    include Pagination

    def results
      paginated(@scope.order(:name, :id))
    end
  end
end

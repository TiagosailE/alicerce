module Inventory
  class WarehousesQuery
    include Pagination

    def results
      paginated(@scope.order(:name, :id))
    end
  end
end

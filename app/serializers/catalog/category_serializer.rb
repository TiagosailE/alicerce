module Catalog
  class CategorySerializer
    def initialize(category)
      @category = category
    end

    def as_json
      { id: @category.id, name: @category.name, active: @category.active }
    end
  end
end

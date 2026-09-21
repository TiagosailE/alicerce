module Inventory
  class WarehouseSerializer
    def initialize(warehouse)
      @warehouse = warehouse
    end

    def as_json
      { id: @warehouse.id, name: @warehouse.name, active: @warehouse.active }
    end
  end
end

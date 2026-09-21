module Catalog
  class UnitSerializer
    def initialize(unit)
      @unit = unit
    end

    def as_json
      { id: @unit.id, code: @unit.code, name: @unit.name, active: @unit.active }
    end
  end
end

module Inventory
  # Error codes: :validation_failed (blank or duplicate name).
  class CreateWarehouse
    def self.call(...) = new(...).call

    def initialize(organization:, name:, actor:)
      @organization = organization
      @name = name
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        warehouse = Inventory::Warehouse.new(organization: @organization, name: @name)
        return Result.invalid(warehouse) unless warehouse.save

        Audit.record("warehouse_created", warehouse, actor: @actor, changes: { name: warehouse.name })
        Result.success(warehouse)
      end
    end
  end
end

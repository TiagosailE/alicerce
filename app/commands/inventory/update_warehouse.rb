module Inventory
  # Error codes: :validation_failed (blank or duplicate name).
  class UpdateWarehouse
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(warehouse:, attributes:, actor:)
      @warehouse = warehouse
      @attributes = attributes
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        return Result.invalid(@warehouse) unless @warehouse.update(@attributes)

        changes = field_changes(@warehouse)
        Audit.record("warehouse_updated", @warehouse, actor: @actor, changes:) if changes.any?
        Result.success(@warehouse)
      end
    end
  end
end

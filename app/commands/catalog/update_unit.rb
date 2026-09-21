module Catalog
  # Error codes: :validation_failed (blank or duplicate code/name).
  class UpdateUnit
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(unit:, attributes:, actor:)
      @unit = unit
      @attributes = attributes
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        return Result.invalid(@unit) unless @unit.update(@attributes)

        changes = field_changes(@unit)
        Audit.record("unit_updated", @unit, actor: @actor, changes:) if changes.any?
        Result.success(@unit)
      end
    end
  end
end

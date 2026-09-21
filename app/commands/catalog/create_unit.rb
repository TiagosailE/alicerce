module Catalog
  # Error codes: :validation_failed (blank or duplicate code/name).
  class CreateUnit
    def self.call(...) = new(...).call

    def initialize(organization:, code:, name:, actor:)
      @organization = organization
      @code = code
      @name = name
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        unit = Catalog::Unit.new(organization: @organization, code: @code, name: @name)
        return Result.invalid(unit) unless unit.save

        Audit.record("unit_created", unit, actor: @actor, changes: { code: unit.code, name: unit.name })
        Result.success(unit)
      end
    end
  end
end

module Catalog
  # Error codes: :validation_failed (blank or duplicate name).
  class UpdateCategory
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(category:, attributes:, actor:)
      @category = category
      @attributes = attributes
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        return Result.invalid(@category) unless @category.update(@attributes)

        changes = field_changes(@category)
        Audit.record("category_updated", @category, actor: @actor, changes:) if changes.any?
        Result.success(@category)
      end
    end
  end
end

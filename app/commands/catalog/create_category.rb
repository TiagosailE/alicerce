module Catalog
  # Error codes: :validation_failed (blank or duplicate name).
  class CreateCategory
    def self.call(...) = new(...).call

    def initialize(organization:, name:, actor:)
      @organization = organization
      @name = name
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        category = Catalog::Category.new(organization: @organization, name: @name)
        return Result.invalid(category) unless category.save

        Audit.record("category_created", category, actor: @actor, changes: { name: category.name })
        Result.success(category)
      end
    end
  end
end

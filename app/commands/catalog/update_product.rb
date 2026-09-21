module Catalog
  # Error codes: :validation_failed (product or conversion fields).
  class UpdateProduct
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(product:, attributes:, actor:, conversion_attributes: nil)
      @product = product
      @attributes = attributes
      @actor = actor
      @conversion_attributes = conversion_attributes
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        unless @product.update(@attributes)
          result = Result.invalid(@product)
          raise ActiveRecord::Rollback
        end

        changes = field_changes(@product)

        if @conversion_attributes
          conversion = @product.unit_conversion
          unless conversion.update(@conversion_attributes)
            result = Result.invalid(conversion)
            raise ActiveRecord::Rollback
          end

          changes.merge!(field_changes(conversion).transform_keys { |field| "unit_conversion.#{field}" })
        end

        Audit.record("product_updated", @product, actor: @actor, changes:) if changes.any?
        result = Result.success(@product)
      end

      result
    end
  end
end

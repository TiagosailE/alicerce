module Catalog
  # revision is the one the caller read (ADR 0015): the row is locked, the
  # revision compared and the write made under that lock, so an edit based on
  # an older read fails instead of silently reverting a newer one.
  #
  # Error codes: :validation_failed (product or conversion fields, or a
  # revision that is not a number), :stale (the product changed since it was
  # read), :conflict_retry (lock wait timed out or deadlocked, safe to retry).
  class UpdateProduct
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(product:, attributes:, actor:, revision:, conversion_attributes: nil)
      @product = product
      @attributes = attributes
      @actor = actor
      @revision = revision
      @conversion_attributes = conversion_attributes
    end

    def call
      return Result.failure(:validation_failed, fields: { "revision" => [ "not_a_number" ] }) unless @revision.is_a?(Integer)

      result = nil

      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        @product.lock!
        if @product.revision != @revision
          result = Result.failure(:stale, current_revision: @product.revision)
          raise ActiveRecord::Rollback
        end

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

        if changes.any?
          @product.increment!(:revision)
          Audit.record("product_updated", @product, actor: @actor, changes:)
        end
        result = Result.success(@product)
      end

      result
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end
  end
end

module Catalog
  # revision is the one the caller read (ADR 0015), checked under a row lock
  # exactly as in UpdateProduct.
  #
  # Error codes: :validation_failed (also a revision that is not a number),
  # :stale, :conflict_retry.
  class UpdatePartner
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(partner:, attributes:, actor:, revision:)
      @partner = partner
      @attributes = attributes
      @actor = actor
      @revision = revision
    end

    def call
      return Result.failure(:validation_failed, fields: { "revision" => [ "not_a_number" ] }) unless @revision.is_a?(Integer)

      result = nil

      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        @partner.lock!("FOR NO KEY UPDATE")
        if @partner.revision != @revision
          result = Result.failure(:stale, current_revision: @partner.revision)
          raise ActiveRecord::Rollback
        end

        unless @partner.update(@attributes)
          result = Result.invalid(@partner)
          raise ActiveRecord::Rollback
        end

        changes = field_changes(@partner)
        Catalog::Partner::PERSONAL_DATA_FIELDS.each { |field| changes[field] = "changed" if changes.key?(field) }
        if changes.any?
          @partner.increment!(:revision)
          Audit.record("partner_updated", @partner, actor: @actor, changes:)
        end
        result = Result.success(@partner)
      end

      result
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end
  end
end

module Catalog
  # Error codes: :validation_failed.
  class UpdatePartner
    include AuditsUpdates

    def self.call(...) = new(...).call

    def initialize(partner:, attributes:, actor:)
      @partner = partner
      @attributes = attributes
      @actor = actor
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        unless @partner.update(@attributes)
          result = Result.invalid(@partner)
          raise ActiveRecord::Rollback
        end

        changes = field_changes(@partner)
        Catalog::Partner::PERSONAL_DATA_FIELDS.each { |field| changes[field] = "changed" if changes.key?(field) }
        Audit.record("partner_updated", @partner, actor: @actor, changes:) if changes.any?
        result = Result.success(@partner)
      end

      result
    end
  end
end

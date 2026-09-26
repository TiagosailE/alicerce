module Purchasing
  # Replaces a draft's supplier, terms, note and lines (ADR 0017). The revision
  # is the one the caller read (ADR 0015); the order is locked and re-read inside
  # the transaction, so what is edited is what is stored, not a copy loaded before
  # someone else's edit or approval.
  #
  # Error codes: :validation_failed, :stale, :invalid_transition (not a draft
  # any more), :conflict_retry.
  class UpdateOrder
    def self.call(...) = new(...).call

    def initialize(order:, actor:, revision:, supplier:, lines:, installments:, first_due_days:, interval_days:, note: nil)
      @order = order
      @actor = actor
      @revision = revision
      @supplier = supplier
      @inputs = lines
      @terms = { installments:, first_due_days:, interval_days: }
      @note = note.presence
    end

    def call
      return Result.failure(:validation_failed, fields: { "revision" => [ "not_a_number" ] }) unless @revision.is_a?(Integer)

      result = nil
      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        result = perform
        raise ActiveRecord::Rollback unless result.success?
      end
      result
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end

    private
      def perform
        order = Purchasing::Order.lock("FOR NO KEY UPDATE").find(@order.id)
        return Result.failure(:invalid_transition) unless order.draft?
        return Result.failure(:stale, current_revision: order.revision) if order.revision != @revision

        fields = Purchasing::OrderRules.supplier_errors(@supplier)
        order.assign_attributes(note: @note, **@terms)
        Purchasing::OrderRules.copy_supplier(order, @supplier) if fields.empty?

        lines, line_fields = Purchasing::BuildLines.call(order:, inputs: @inputs)
        fields.merge!(line_fields)
        fields.merge!(Purchasing::OrderRules.total_errors(lines)) if line_fields.empty?
        order.total_cents = Purchasing::OrderRules.total_cents(lines)
        order.validate
        order.errors.each { |error| (fields[error.attribute.to_s] ||= []) << error.type.to_s }
        return Result.failure(:validation_failed, fields:) if fields.any?

        order.lines.reset
        order.lines.destroy_all
        order.lines = lines
        order.revision += 1
        order.save!
        Audit.record("purchase_order_updated", order, actor: @actor,
          changes: { number: order.number, supplier_id: order.supplier_id, total_cents: order.total_cents, lines: lines.size })
        Result.success(order)
      end
  end
end

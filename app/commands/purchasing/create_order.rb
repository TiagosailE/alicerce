module Purchasing
  # Creates a draft purchase order with its lines (ADR 0017): copies the
  # supplier and each product as they are now, works out every line's amounts
  # and the order's total, and takes the next order number from the counter (the
  # last lock, ADR 0004, so a rollback returns it).
  #
  # Error codes: :validation_failed (fields "supplier_id", "installments", "note",
  # "lines" and "lines.N.<field>"), :conflict_retry.
  class CreateOrder
    def self.call(...) = new(...).call

    def initialize(organization:, actor:, supplier:, lines:, installments: 1, first_due_days: 30, interval_days: 30, note: nil)
      @organization = organization
      @actor = actor
      @supplier = supplier
      @inputs = lines
      @terms = { installments:, first_due_days:, interval_days: }
      @note = note.presence
    end

    def call
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
        order = Purchasing::Order.new(organization: @organization, created_by_user: @actor, supplier: @supplier, note: @note, **@terms)
        fields = Purchasing::OrderRules.supplier_errors(@supplier)
        Purchasing::OrderRules.copy_supplier(order, @supplier) if fields.empty?

        lines, line_fields = Purchasing::BuildLines.call(order:, inputs: @inputs)
        fields.merge!(line_fields)
        fields.merge!(Purchasing::OrderRules.total_errors(lines)) if line_fields.empty?
        order.total_cents = Purchasing::OrderRules.total_cents(lines)
        order.validate
        order.errors.each { |error| (fields[error.attribute.to_s] ||= []) << error.type.to_s }
        return Result.failure(:validation_failed, fields:) if fields.any?

        order.number = DocumentCounter.next!(organization: @organization, kind: "purchase_order")
        order.lines = lines
        order.save!
        Audit.record("purchase_order_created", order, actor: @actor,
          changes: { number: order.number, supplier_id: order.supplier_id, total_cents: order.total_cents, lines: lines.size })
        Result.success(order)
      end
  end
end

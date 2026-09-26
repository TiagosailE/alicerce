module Purchasing
  # Approves a draft (ADR 0017). The approver sends the revision they saw, so an
  # edit made between their read and their click is refused as stale instead of
  # approved unseen (ADR 0015). Approval checks that the order can ever be
  # received (lines, prices, an active supplier and products with a conversion,
  # amounts within the cap) and copies the supplier's and each product's
  # descriptive data again, which is what freezes them. It never changes what
  # the approver saw in money: if a product's purchase unit or factor changed
  # since the draft was saved, the approval is refused (fields
  # "lines.N.conversion" => ["changed"]) and saving the draft again refreshes the
  # copy, bumps the revision and shows the approver the new terms.
  #
  # Error codes: :validation_failed, :stale, :invalid_transition, :conflict_retry.
  class ApproveOrder
    def self.call(...) = new(...).call

    def initialize(order:, actor:, revision:)
      @order = order
      @actor = actor
      @revision = revision
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
        return Result.failure(:invalid_transition) unless order.can_transition_to?("approved")
        return Result.failure(:stale, current_revision: order.revision) if order.revision != @revision

        fields = Purchasing::OrderRules.supplier_errors(order.supplier)
        lines = order.lines.includes(product: %i[unit_conversion stock_unit]).to_a
        fields["lines"] = [ "blank" ] if lines.empty?
        lines.each_with_index { |line, index| refresh(line, index, fields) }
        fields.merge!(Purchasing::OrderRules.total_errors(lines)) if fields.empty?
        return Result.failure(:validation_failed, fields:) if fields.any?

        lines.each(&:save!)
        Purchasing::OrderRules.copy_supplier(order, order.supplier)
        order.total_cents = Purchasing::OrderRules.total_cents(lines)
        order.transition_to!(:approved, approved_at: Time.current, approved_by_user: @actor, revision: order.revision + 1)
        Audit.record("purchase_order_approved", order, actor: @actor,
          changes: { number: order.number, status: { from: "draft", to: "approved" }, total_cents: order.total_cents })
        Result.success(order)
      end

      def conversion_changed?(line, conversion)
        conversion.purchase_unit_id != line.purchase_unit_id || conversion.factor != line.factor
      end

      def refresh(line, index, fields)
        product = line.product
        if !product.active?
          (fields["lines.#{index}.product_id"] ||= []) << "inactive"
        elsif product.unit_conversion.nil?
          (fields["lines.#{index}.product_id"] ||= []) << "conversion_missing"
        elsif conversion_changed?(line, product.unit_conversion)
          (fields["lines.#{index}.conversion"] ||= []) << "changed"
        else
          line.copy_from(product)
        end
        (fields["lines.#{index}.unit_price_cents"] ||= []) << "must_be_positive" unless line.unit_price_cents.to_i.positive?
      end
  end
end

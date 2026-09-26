module Purchasing
  # Cancels an order (ADR 0017): a draft or approved order simply ends; a
  # partially received one is closed at what has been received, which stays.
  # A receipt in flight cannot be missed: both take the order's lock and decide
  # from the row they re-read under it.
  #
  # Error codes: :invalid_transition, :conflict_retry.
  class CancelOrder
    def self.call(...) = new(...).call

    def initialize(order:, actor:)
      @order = order
      @actor = actor
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
        order = Purchasing::Order.lock("FOR NO KEY UPDATE").find(@order.id)
        return Result.failure(:invalid_transition) unless order.can_transition_to?("cancelled")

        from = order.status
        order.transition_to!(:cancelled, cancelled_at: Time.current, cancelled_by_user: @actor, revision: order.revision + 1)
        Audit.record("purchase_order_cancelled", order, actor: @actor,
          changes: { number: order.number, status: { from:, to: "cancelled" } })
        Result.success(order)
      end
  end
end

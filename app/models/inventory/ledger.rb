module Inventory
  # The only writer of the movement ledger and of a balance's quantities and
  # value (ADR 0016). Every stock command (adjustments now, receipts, issues and
  # reversals later) posts through here, so the rule that a movement and its
  # balance change together, and that the balance always equals the sum of its
  # movements, lives in one place instead of once per command.
  #
  # It does no transaction and no locking of its own: the caller has already
  # locked the balance (Balance.lock_for) inside its own transaction, which
  # keeps this composable inside a larger command. It also does no valuation:
  # the caller decides what the movement is worth.
  module Ledger
    # A value the movement and its running total may reach, in cents. Far above
    # any real distributor (R$ 10 trillion) and far below bigint, so a typo can
    # never turn into a database range error.
    VALUE_CAP_CENTS = 10**15

    module_function

    def fits?(balance, value_cents)
      value_cents.abs <= VALUE_CAP_CENTS && (balance.value_cents + value_cents).abs <= VALUE_CAP_CENTS
    end

    def post(balance:, kind:, quantity:, value_cents:, actor:, reason: nil, note: nil, last_unit_cost: nil)
      raise ArgumentError, "value out of range" unless fits?(balance, value_cents)

      on_hand_after = balance.on_hand + quantity
      value_after = balance.value_cents + value_cents
      movement = Inventory::Movement.create!(
        organization_id: balance.organization_id, product_id: balance.product_id, warehouse_id: balance.warehouse_id,
        kind:, quantity:, value_cents:, on_hand_after:, value_after_cents: value_after, reason:, note:, actor_user: actor
      )
      balance.update!(on_hand: on_hand_after, value_cents: value_after, last_unit_cost: last_unit_cost || balance.last_unit_cost)
      movement
    end
  end
end

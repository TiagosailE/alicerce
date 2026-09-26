module Inventory
  # The only writer of the movement ledger and of a balance's quantities and
  # value (ADR 0016). Every stock command (adjustments now, receipts, issues and
  # reversals later) posts through here, so the rule that a movement and its
  # balance change together, and that the balance always equals the sum of its
  # movements, lives in one place instead of once per command.
  #
  # It opens no transaction and takes no lock the caller does not already hold:
  # the balance was locked by Balance.lock_for inside the caller's own
  # transaction, which keeps this composable inside a larger command. It does
  # re-read the row under that lock rather than trust the instance it was
  # handed, so a caller holding a stale copy (a second instance loaded before
  # an earlier line of the same document posted) can never make the movement's
  # "after" figures, or the balance, drift from the ledger. It does no
  # valuation: the caller decides what the movement is worth.
  module Ledger
    # A value the movement and its running total may reach, in cents. Far above
    # any real distributor (R$ 10 trillion) and far below bigint, so a typo can
    # never turn into a database range error.
    VALUE_CAP_CENTS = 10**15

    module_function

    def fits?(balance, value_cents)
      value_cents.abs <= VALUE_CAP_CENTS && (balance.value_cents + value_cents).abs <= VALUE_CAP_CENTS
    end

    def post(balance:, kind:, quantity:, value_cents:, actor:, reason: nil, note: nil, last_unit_cost: nil, receipt_line_id: nil)
      current = Inventory::Balance.lock("FOR NO KEY UPDATE").find(balance.id)
      raise ArgumentError, "value out of range" unless fits?(current, value_cents)

      on_hand_after = current.on_hand + quantity
      value_after = current.value_cents + value_cents
      movement = Inventory::Movement.create!(
        organization_id: current.organization_id, product_id: current.product_id, warehouse_id: current.warehouse_id,
        kind:, quantity:, value_cents:, on_hand_after:, value_after_cents: value_after, reason:, note:, actor_user: actor,
        receipt_line_id:
      )
      current.update!(on_hand: on_hand_after, value_cents: value_after, last_unit_cost: last_unit_cost || current.last_unit_cost)
      balance.reload
      movement
    end
  end
end

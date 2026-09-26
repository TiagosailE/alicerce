class ValidateApprovalStamp < ActiveRecord::Migration[8.1]
  # Second step of 20260926170100. No down: a validated constraint has nothing to undo.
  def up
    validate_check_constraint :purchasing_orders, name: "purchasing_orders_approval_stamped"
  end

  def down; end
end

class AddReceiptsToInventoryMovements < ActiveRecord::Migration[8.1]
  # ADR 0017: a movement can be a receipt, tied to the receipt line that created
  # it by a typed, composite-keyed column (not a polymorphic source, which cannot
  # carry the tenant key). The constraints on the existing table are added NOT
  # VALID and validated in a following migration; the unique index is built
  # concurrently in its own.
  def up
    add_column :inventory_movements, :receipt_line_id, :bigint

    remove_check_constraint :inventory_movements, name: "inventory_movements_kind_valid"
    add_check_constraint :inventory_movements, "kind IN ('adjustment', 'receipt')",
      name: "inventory_movements_kind_valid", validate: false
    # A receipt moves stock in (a positive quantity: the existing value check
    # would let a zero quantity carry any value), has no reason, and has its line;
    # only a receipt has one.
    add_check_constraint :inventory_movements,
      "kind <> 'receipt' OR (quantity > 0 AND reason IS NULL AND receipt_line_id IS NOT NULL)",
      name: "inventory_movements_receipt_shape", validate: false
    add_check_constraint :inventory_movements, "receipt_line_id IS NULL OR kind = 'receipt'",
      name: "inventory_movements_only_receipts_have_a_line", validate: false

    # The line's own product and warehouse: the movement is one balance's, and the
    # line it points at must be that balance's too. A null receipt_line_id skips
    # the check (MATCH SIMPLE), which is every movement that is not a receipt.
    add_foreign_key :inventory_movements, :purchasing_receipt_lines,
      column: [ :organization_id, :receipt_line_id, :product_id, :warehouse_id ],
      primary_key: [ :organization_id, :id, :product_id, :warehouse_id ],
      name: "fk_inventory_movements_receipt_line_same_balance", validate: false
  end

  def down
    remove_foreign_key :inventory_movements, name: "fk_inventory_movements_receipt_line_same_balance"
    remove_check_constraint :inventory_movements, name: "inventory_movements_only_receipts_have_a_line"
    remove_check_constraint :inventory_movements, name: "inventory_movements_receipt_shape"
    remove_check_constraint :inventory_movements, name: "inventory_movements_kind_valid"
    add_check_constraint :inventory_movements, "kind IN ('adjustment')", name: "inventory_movements_kind_valid"
    remove_column :inventory_movements, :receipt_line_id
  end
end

class ValidateInventoryForeignKeys < ActiveRecord::Migration[8.1]
  # Second step of the two migrations before it: the composite keys to
  # products and warehouses were added NOT VALID so creating the ledger tables
  # does not block writes on those tables. No down: a validated constraint has
  # nothing to undo, and rolling back the create migrations drops the keys.
  def up
    validate_foreign_key :inventory_balances, name: "fk_inventory_balances_product_same_organization"
    validate_foreign_key :inventory_balances, name: "fk_inventory_balances_warehouse_same_organization"
    validate_foreign_key :inventory_movements, name: "fk_inventory_movements_product_same_organization"
    validate_foreign_key :inventory_movements, name: "fk_inventory_movements_warehouse_same_organization"
  end

  def down; end
end

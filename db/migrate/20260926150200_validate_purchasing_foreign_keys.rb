class ValidatePurchasingForeignKeys < ActiveRecord::Migration[8.1]
  # Second step of the two migrations before it (they add the composite keys
  # NOT VALID so creating the tables does not block writes on the tables they
  # reference). No down: a validated constraint has nothing to undo.
  def up
    validate_foreign_key :purchasing_orders, name: "fk_purchasing_orders_supplier_same_organization"
    validate_foreign_key :purchasing_order_lines, name: "fk_purchasing_order_lines_order_same_organization"
    validate_foreign_key :purchasing_order_lines, name: "fk_purchasing_order_lines_product_same_organization"
    validate_foreign_key :purchasing_order_lines, name: "fk_purchasing_order_lines_unit_same_organization"
  end

  def down; end
end

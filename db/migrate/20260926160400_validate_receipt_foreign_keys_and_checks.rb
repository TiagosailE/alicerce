class ValidateReceiptForeignKeysAndChecks < ActiveRecord::Migration[8.1]
  # Second step of the four migrations before it. No down: a validated
  # constraint has nothing to undo.
  def up
    validate_foreign_key :purchasing_receipts, name: "fk_purchasing_receipts_order_same_organization"
    validate_foreign_key :purchasing_receipts, name: "fk_purchasing_receipts_warehouse_same_organization"
    validate_foreign_key :purchasing_receipt_lines, name: "fk_purchasing_receipt_lines_receipt_same_order"
    validate_foreign_key :purchasing_receipt_lines, name: "fk_purchasing_receipt_lines_receipt_same_warehouse"
    validate_foreign_key :purchasing_receipt_lines, name: "fk_purchasing_receipt_lines_order_line_same_order"
    validate_foreign_key :purchasing_receipt_lines, name: "fk_purchasing_receipt_lines_product_same_organization"
    validate_foreign_key :finance_titles, name: "fk_finance_titles_partner_same_organization"
    validate_foreign_key :finance_titles, name: "fk_finance_titles_receipt_same_organization"
    validate_foreign_key :finance_installments, name: "fk_finance_installments_title_same_organization"
    validate_foreign_key :inventory_movements, name: "fk_inventory_movements_receipt_line_same_balance"

    validate_check_constraint :inventory_movements, name: "inventory_movements_kind_valid"
    validate_check_constraint :inventory_movements, name: "inventory_movements_receipt_shape"
    validate_check_constraint :inventory_movements, name: "inventory_movements_only_receipts_have_a_line"
  end

  def down; end
end

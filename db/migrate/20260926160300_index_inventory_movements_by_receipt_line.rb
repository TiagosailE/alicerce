class IndexInventoryMovementsByReceiptLine < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # A receipt line enters stock at most once.
  def change
    add_index :inventory_movements, :receipt_line_id, unique: true, where: "receipt_line_id IS NOT NULL",
      name: "index_inventory_movements_on_receipt_line_id", algorithm: :concurrently
  end
end

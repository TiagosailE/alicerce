class CreatePurchasingOrderLines < ActiveRecord::Migration[8.1]
  # ADR 0017. The product's sku and name, the purchase unit and the factor are
  # copied when the line is saved and frozen at approval. The line's amounts are
  # stored; what has been received is kept on the line, updated only by
  # Purchasing::ReceiveGoods under the order's lock.
  def up
    create_table :purchasing_order_lines do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :order_id, null: false
      t.integer :position, null: false
      t.bigint :product_id, null: false
      t.string :product_sku, null: false
      t.string :product_name, null: false
      t.bigint :purchase_unit_id, null: false
      t.string :purchase_unit_code, null: false
      t.string :stock_unit_code, null: false
      t.decimal :factor, precision: 15, scale: 6, null: false
      t.decimal :quantity, precision: 15, scale: 3, null: false
      t.bigint :unit_price_cents, null: false
      t.integer :discount_bp, null: false, default: 0
      t.bigint :gross_cents, null: false
      t.bigint :discount_cents, null: false
      t.bigint :net_cents, null: false
      t.decimal :received_quantity, precision: 15, scale: 3, null: false, default: 0
      t.decimal :received_stock_quantity, precision: 15, scale: 3, null: false, default: 0
      t.bigint :received_gross_cents, null: false, default: 0
      t.bigint :received_discount_cents, null: false, default: 0
      t.timestamps
    end

    add_index :purchasing_order_lines, [ :organization_id, :order_id, :id ], unique: true,
      name: "index_purchasing_order_lines_on_organization_order_and_id"
    add_index :purchasing_order_lines, [ :order_id, :position ], unique: true
    add_index :purchasing_order_lines, [ :organization_id, :product_id ]

    add_foreign_key :purchasing_order_lines, :purchasing_orders,
      column: [ :organization_id, :order_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_order_same_organization", validate: false
    add_foreign_key :purchasing_order_lines, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_product_same_organization", validate: false
    add_foreign_key :purchasing_order_lines, :catalog_units,
      column: [ :organization_id, :purchase_unit_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_unit_same_organization", validate: false

    add_check_constraint :purchasing_order_lines, "quantity > 0", name: "purchasing_order_lines_quantity_positive"
    add_check_constraint :purchasing_order_lines, "factor > 0", name: "purchasing_order_lines_factor_positive"
    add_check_constraint :purchasing_order_lines, "unit_price_cents >= 0", name: "purchasing_order_lines_price_not_negative"
    add_check_constraint :purchasing_order_lines, "discount_bp BETWEEN 0 AND 10000", name: "purchasing_order_lines_discount_range"
    add_check_constraint :purchasing_order_lines,
      "gross_cents >= 0 AND discount_cents >= 0 AND discount_cents <= gross_cents AND net_cents = gross_cents - discount_cents",
      name: "purchasing_order_lines_amounts_consistent"
    add_check_constraint :purchasing_order_lines, "gross_cents <= 1000000000000000", name: "purchasing_order_lines_gross_cap"
    add_check_constraint :purchasing_order_lines,
      "received_quantity BETWEEN 0 AND quantity AND received_stock_quantity >= 0 " \
      "AND received_gross_cents BETWEEN 0 AND gross_cents AND received_discount_cents BETWEEN 0 AND discount_cents",
      name: "purchasing_order_lines_received_within_line"

    safety_assured do
      execute <<~SQL
        ALTER TABLE purchasing_order_lines ENABLE ROW LEVEL SECURITY;

        CREATE POLICY purchasing_order_lines_tenant_isolation ON purchasing_order_lines
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :purchasing_order_lines
  end
end

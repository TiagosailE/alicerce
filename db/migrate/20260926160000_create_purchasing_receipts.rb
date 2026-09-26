class CreatePurchasingReceipts < ActiveRecord::Migration[8.1]
  # ADR 0017. A receipt is a posted document: append-only like the ledger it
  # writes to (no UPDATE, DELETE or TRUNCATE for the app role, a trigger for
  # everyone but the owner). A receipt line belongs to the receipt's own order
  # through one composite key, is unique per receipt, and copies what it was
  # priced with, so the receipt stands on its own.
  def up
    create_table :purchasing_receipts do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :number, null: false
      t.bigint :order_id, null: false
      t.bigint :warehouse_id, null: false
      t.date :received_on, null: false
      t.string :supplier_invoice_number
      t.bigint :total_cents, null: false, default: 0
      t.string :status, null: false, default: "posted"
      t.string :currency, limit: 3, null: false, default: "BRL"
      t.references :created_by_user, null: false, foreign_key: { to_table: :identity_users }
      t.datetime :created_at, null: false
    end

    add_index :purchasing_receipts, [ :organization_id, :number ], unique: true,
      name: "index_purchasing_receipts_on_organization_id_and_number"
    add_index :purchasing_receipts, [ :organization_id, :id ], unique: true,
      name: "index_purchasing_receipts_on_organization_id_and_id"
    add_index :purchasing_receipts, [ :organization_id, :order_id, :id ], unique: true,
      name: "index_purchasing_receipts_on_organization_order_and_id"
    add_index :purchasing_receipts, [ :organization_id, :received_on ]

    add_foreign_key :purchasing_receipts, :purchasing_orders,
      column: [ :organization_id, :order_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_receipts_order_same_organization", validate: false
    add_foreign_key :purchasing_receipts, :inventory_warehouses,
      column: [ :organization_id, :warehouse_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_receipts_warehouse_same_organization", validate: false

    add_check_constraint :purchasing_receipts, "status = 'posted'", name: "purchasing_receipts_status_valid"
    add_check_constraint :purchasing_receipts, "total_cents BETWEEN 0 AND 1000000000000000", name: "purchasing_receipts_total_range"
    add_check_constraint :purchasing_receipts, "currency = 'BRL'", name: "purchasing_receipts_currency_brl"

    create_table :purchasing_receipt_lines do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :receipt_id, null: false
      t.bigint :order_id, null: false
      t.bigint :order_line_id, null: false
      t.bigint :product_id, null: false
      t.string :product_sku, null: false
      t.string :product_name, null: false
      t.string :purchase_unit_code, null: false
      t.string :stock_unit_code, null: false
      t.decimal :factor, precision: 15, scale: 6, null: false
      t.bigint :unit_price_cents, null: false
      t.integer :discount_bp, null: false
      t.decimal :quantity, precision: 15, scale: 3, null: false
      t.decimal :stock_quantity, precision: 15, scale: 3, null: false
      t.bigint :gross_cents, null: false
      t.bigint :discount_cents, null: false
      t.bigint :net_cents, null: false
      t.datetime :created_at, null: false
    end

    add_index :purchasing_receipt_lines, [ :receipt_id, :order_line_id ], unique: true,
      name: "index_purchasing_receipt_lines_on_receipt_and_order_line"
    add_index :purchasing_receipt_lines, [ :organization_id, :id ], unique: true,
      name: "index_purchasing_receipt_lines_on_organization_id_and_id"
    add_index :purchasing_receipt_lines, [ :organization_id, :order_line_id ]

    add_foreign_key :purchasing_receipt_lines, :purchasing_receipts,
      column: [ :organization_id, :order_id, :receipt_id ], primary_key: [ :organization_id, :order_id, :id ],
      name: "fk_purchasing_receipt_lines_receipt_same_order", validate: false
    add_foreign_key :purchasing_receipt_lines, :purchasing_order_lines,
      column: [ :organization_id, :order_id, :order_line_id ], primary_key: [ :organization_id, :order_id, :id ],
      name: "fk_purchasing_receipt_lines_order_line_same_order", validate: false
    add_foreign_key :purchasing_receipt_lines, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_receipt_lines_product_same_organization", validate: false

    add_check_constraint :purchasing_receipt_lines, "quantity > 0 AND stock_quantity > 0", name: "purchasing_receipt_lines_moves_stock"
    add_check_constraint :purchasing_receipt_lines,
      "gross_cents >= 0 AND discount_cents >= 0 AND discount_cents <= gross_cents AND net_cents = gross_cents - discount_cents",
      name: "purchasing_receipt_lines_amounts_consistent"
    add_check_constraint :purchasing_receipt_lines, "discount_bp BETWEEN 0 AND 10000", name: "purchasing_receipt_lines_discount_range"

    safety_assured do
      execute <<~SQL
        ALTER TABLE purchasing_receipts ENABLE ROW LEVEL SECURITY;
        CREATE POLICY purchasing_receipts_tenant_isolation ON purchasing_receipts
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);

        ALTER TABLE purchasing_receipt_lines ENABLE ROW LEVEL SECURITY;
        CREATE POLICY purchasing_receipt_lines_tenant_isolation ON purchasing_receipt_lines
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);

        -- Append-only, enforced twice (the revoke below and this trigger), as the
        -- ledger is: a posted receipt is never edited, a mistake is corrected by a
        -- new record. Compares against the real table owner, not a role name.
        CREATE FUNCTION purchasing_receipts_append_only() RETURNS trigger AS $$
        BEGIN
          IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = TG_TABLE_NAME) THEN
            RAISE EXCEPTION '% is append-only: % is not permitted for %', TG_TABLE_NAME, TG_OP, current_user;
          END IF;
          RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;

        CREATE FUNCTION purchasing_receipts_no_truncate() RETURNS trigger AS $$
        BEGIN
          IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = TG_TABLE_NAME) THEN
            RAISE EXCEPTION '% is append-only: TRUNCATE is not permitted for %', TG_TABLE_NAME, current_user;
          END IF;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER purchasing_receipts_append_only BEFORE UPDATE OR DELETE ON purchasing_receipts
          FOR EACH ROW EXECUTE FUNCTION purchasing_receipts_append_only();
        CREATE TRIGGER purchasing_receipts_no_truncate BEFORE TRUNCATE ON purchasing_receipts
          FOR EACH STATEMENT EXECUTE FUNCTION purchasing_receipts_no_truncate();
        CREATE TRIGGER purchasing_receipt_lines_append_only BEFORE UPDATE OR DELETE ON purchasing_receipt_lines
          FOR EACH ROW EXECUTE FUNCTION purchasing_receipts_append_only();
        CREATE TRIGGER purchasing_receipt_lines_no_truncate BEFORE TRUNCATE ON purchasing_receipt_lines
          FOR EACH STATEMENT EXECUTE FUNCTION purchasing_receipts_no_truncate();

        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'REVOKE UPDATE, DELETE ON purchasing_receipts, purchasing_receipt_lines FROM alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER IF EXISTS purchasing_receipt_lines_no_truncate ON purchasing_receipt_lines;
        DROP TRIGGER IF EXISTS purchasing_receipt_lines_append_only ON purchasing_receipt_lines;
        DROP TRIGGER IF EXISTS purchasing_receipts_no_truncate ON purchasing_receipts;
        DROP TRIGGER IF EXISTS purchasing_receipts_append_only ON purchasing_receipts;
        DROP FUNCTION IF EXISTS purchasing_receipts_no_truncate();
        DROP FUNCTION IF EXISTS purchasing_receipts_append_only();
      SQL
    end

    drop_table :purchasing_receipt_lines
    drop_table :purchasing_receipts
  end
end

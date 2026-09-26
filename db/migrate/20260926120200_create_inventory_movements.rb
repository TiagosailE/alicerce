class CreateInventoryMovements < ActiveRecord::Migration[8.1]
  # The ledger (ADR 0016): immutable, every row a signed quantity and value,
  # with the balance after it. Corrections are new rows. Append-only enforced
  # twice, like the audit trail (ADR 0010): the app role has no UPDATE or
  # DELETE, and a trigger stops every role but the table owner.
  def up
    create_table :inventory_movements do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :product_id, null: false
      t.bigint :warehouse_id, null: false
      t.string :kind, null: false
      t.decimal :quantity, precision: 15, scale: 3, null: false
      t.bigint :value_cents, null: false
      t.string :currency, limit: 3, null: false, default: "BRL"
      t.decimal :on_hand_after, precision: 15, scale: 3, null: false
      t.bigint :value_after_cents, null: false
      t.string :reason
      t.text :note
      t.references :actor_user, null: false, foreign_key: { to_table: :identity_users }
      t.datetime :created_at, null: false
    end

    add_index :inventory_movements, [ :organization_id, :created_at ]
    add_index :inventory_movements, [ :organization_id, :product_id, :created_at ],
      name: "index_inventory_movements_on_organization_product_and_time"
    add_index :inventory_movements, [ :organization_id, :warehouse_id, :created_at ],
      name: "index_inventory_movements_on_organization_warehouse_and_time"
    add_index :inventory_movements, [ :organization_id, :id ], unique: true,
      name: "index_inventory_movements_on_organization_id_and_id"

    add_foreign_key :inventory_movements, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_inventory_movements_product_same_organization", validate: false
    add_foreign_key :inventory_movements, :inventory_warehouses,
      column: [ :organization_id, :warehouse_id ], primary_key: [ :organization_id, :id ],
      name: "fk_inventory_movements_warehouse_same_organization", validate: false

    add_check_constraint :inventory_movements, "kind IN ('adjustment')",
      name: "inventory_movements_kind_valid"
    add_check_constraint :inventory_movements,
      "reason IS NULL OR reason IN ('opening_balance', 'count', 'loss', 'damage', 'theft', 'expiry', 'found', 'other')",
      name: "inventory_movements_reason_valid"
    add_check_constraint :inventory_movements, "kind <> 'adjustment' OR reason IS NOT NULL",
      name: "inventory_movements_adjustment_has_reason"
    add_check_constraint :inventory_movements, "kind <> 'adjustment' OR quantity <> 0",
      name: "inventory_movements_adjustment_moves_stock"
    add_check_constraint :inventory_movements,
      "(quantity > 0 AND value_cents >= 0) OR (quantity < 0 AND value_cents <= 0) OR quantity = 0",
      name: "inventory_movements_value_follows_quantity"
    add_check_constraint :inventory_movements, "currency = 'BRL'",
      name: "inventory_movements_currency_brl"

    safety_assured do
      execute <<~SQL
        ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;

        CREATE POLICY inventory_movements_tenant_isolation ON inventory_movements
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);

        CREATE FUNCTION inventory_movements_append_only() RETURNS trigger AS $$
        BEGIN
          IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'inventory_movements') THEN
            RAISE EXCEPTION 'inventory_movements is append-only: % is not permitted for %', TG_OP, current_user;
          END IF;

          RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER inventory_movements_append_only
          BEFORE UPDATE OR DELETE ON inventory_movements
          FOR EACH ROW EXECUTE FUNCTION inventory_movements_append_only();

        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'REVOKE UPDATE, DELETE ON inventory_movements FROM alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER IF EXISTS inventory_movements_append_only ON inventory_movements;
        DROP FUNCTION IF EXISTS inventory_movements_append_only();
      SQL
    end

    drop_table :inventory_movements
  end
end

class CreateInventoryBalances < ActiveRecord::Migration[8.1]
  # The row that gets locked (ADR 0004): one per product and warehouse, holding
  # the quantities and the inventory value (ADR 0006, ADR 0016). Created only by
  # Inventory::Balance.lock_for. The checks state the invariants the domain
  # also enforces, so a bug or a raw write cannot break them silently.
  def up
    create_table :inventory_balances do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :product_id, null: false
      t.bigint :warehouse_id, null: false
      t.decimal :on_hand, precision: 15, scale: 3, null: false, default: 0
      t.decimal :reserved, precision: 15, scale: 3, null: false, default: 0
      t.decimal :negative_allowance, precision: 15, scale: 3, null: false, default: 0
      t.bigint :value_cents, null: false, default: 0
      t.decimal :last_unit_cost, precision: 19, scale: 6, null: false, default: 0
      t.string :currency, limit: 3, null: false, default: "BRL"
      t.timestamps
    end

    add_index :inventory_balances, [ :organization_id, :product_id, :warehouse_id ], unique: true,
      name: "index_inventory_balances_on_organization_product_and_warehouse"
    add_index :inventory_balances, [ :organization_id, :warehouse_id ]
    add_index :inventory_balances, [ :organization_id, :id ], unique: true,
      name: "index_inventory_balances_on_organization_id_and_id"

    add_foreign_key :inventory_balances, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_inventory_balances_product_same_organization", validate: false
    add_foreign_key :inventory_balances, :inventory_warehouses,
      column: [ :organization_id, :warehouse_id ], primary_key: [ :organization_id, :id ],
      name: "fk_inventory_balances_warehouse_same_organization", validate: false

    add_check_constraint :inventory_balances, "on_hand >= -negative_allowance",
      name: "inventory_balances_on_hand_within_allowance"
    add_check_constraint :inventory_balances, "reserved >= 0",
      name: "inventory_balances_reserved_not_negative"
    add_check_constraint :inventory_balances, "negative_allowance >= 0",
      name: "inventory_balances_allowance_not_negative"
    add_check_constraint :inventory_balances,
      "(on_hand > 0 AND value_cents >= 0) OR (on_hand < 0 AND value_cents <= 0) OR (on_hand = 0 AND value_cents = 0)",
      name: "inventory_balances_value_follows_stock"
    add_check_constraint :inventory_balances, "last_unit_cost >= 0",
      name: "inventory_balances_last_unit_cost_not_negative"
    add_check_constraint :inventory_balances, "currency = 'BRL'",
      name: "inventory_balances_currency_brl"

    safety_assured do
      execute <<~SQL
        ALTER TABLE inventory_balances ENABLE ROW LEVEL SECURITY;

        CREATE POLICY inventory_balances_tenant_isolation ON inventory_balances
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :inventory_balances
  end
end

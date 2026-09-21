class CreateInventoryWarehouses < ActiveRecord::Migration[8.1]
  def up
    create_table :inventory_warehouses do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :inventory_warehouses, "organization_id, lower(name)", unique: true,
      name: "index_inventory_warehouses_on_organization_id_and_lower_name"

    # Lets a future inventory_balances.warehouse_id reference
    # (organization_id, warehouse_id) as a composite foreign key, the same
    # reason catalog_categories has this index (see its migration): row
    # level security does not apply to foreign key checks, so without it a
    # referencing row could point at another organization's warehouse.
    add_index :inventory_warehouses, [ :organization_id, :id ], unique: true,
      name: "index_inventory_warehouses_on_organization_id_and_id"

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE inventory_warehouses ENABLE ROW LEVEL SECURITY;

        CREATE POLICY inventory_warehouses_tenant_isolation ON inventory_warehouses
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :inventory_warehouses
  end
end

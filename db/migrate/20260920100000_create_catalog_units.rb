class CreateCatalogUnits < ActiveRecord::Migration[8.1]
  def up
    create_table :catalog_units do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :code, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :catalog_units, [ :organization_id, :code ], unique: true

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE catalog_units ENABLE ROW LEVEL SECURITY;

        CREATE POLICY catalog_units_tenant_isolation ON catalog_units
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :catalog_units
  end
end

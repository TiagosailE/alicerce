class CreateCatalogUnitConversions < ActiveRecord::Migration[8.1]
  def up
    create_table :catalog_unit_conversions do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.references :product, null: false, foreign_key: { to_table: :catalog_products }, index: { unique: true }
      t.references :purchase_unit, null: false, foreign_key: { to_table: :catalog_units }
      t.decimal :factor, null: false, precision: 15, scale: 6
      t.timestamps
    end

    add_check_constraint :catalog_unit_conversions, "factor > 0", name: "catalog_unit_conversions_factor_positive"

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE catalog_unit_conversions ENABLE ROW LEVEL SECURITY;

        CREATE POLICY catalog_unit_conversions_tenant_isolation ON catalog_unit_conversions
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :catalog_unit_conversions
  end
end

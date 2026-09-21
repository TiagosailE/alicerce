class CreateCatalogCategories < ActiveRecord::Migration[8.1]
  def up
    create_table :catalog_categories do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :catalog_categories, "organization_id, lower(name)", unique: true,
      name: "index_catalog_categories_on_organization_id_and_lower_name"

    # Lets catalog_products reference (organization_id, category_id) as a
    # composite foreign key, so a cross-organization category_id is refused
    # by Postgres itself, not only by the model validation: row level
    # security does not apply to foreign key checks (a referencing row can
    # otherwise point at a row RLS would hide), the reason this exists.
    add_index :catalog_categories, [ :organization_id, :id ], unique: true,
      name: "index_catalog_categories_on_organization_id_and_id"

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE catalog_categories ENABLE ROW LEVEL SECURITY;

        CREATE POLICY catalog_categories_tenant_isolation ON catalog_categories
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :catalog_categories
  end
end

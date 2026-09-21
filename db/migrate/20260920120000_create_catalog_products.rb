class CreateCatalogProducts < ActiveRecord::Migration[8.1]
  def up
    create_table :catalog_products do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :sku, null: false
      t.string :name, null: false
      t.references :category
      t.references :stock_unit, null: false, foreign_key: { to_table: :catalog_units }
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :catalog_products, "organization_id, lower(sku)", unique: true,
      name: "index_catalog_products_on_organization_id_and_lower_sku"

    # A composite foreign key on (organization_id, category_id): category is
    # optional, so nothing forces Rails to load and validate it the way a
    # required belongs_to (stock_unit above) already does for free. Without
    # this, a category_id for another organization would reach the database
    # unchecked, since row level security does not apply to foreign key
    # checks (Catalog::Product's own model validation is the other half of
    # this fix, for the ordinary 422 a request should get instead of an
    # unhandled foreign key error).
    # safety_assured: catalog_products was just created by this same
    # migration, so it holds no rows yet; strong_migrations' concern
    # (validating a foreign key locks and scans an existing table) does not
    # apply here.
    safety_assured do
      add_foreign_key :catalog_products, :catalog_categories,
        column: [ :organization_id, :category_id ], primary_key: [ :organization_id, :id ],
        name: "fk_catalog_products_category_same_organization"
    end

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE catalog_products ENABLE ROW LEVEL SECURITY;

        CREATE POLICY catalog_products_tenant_isolation ON catalog_products
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :catalog_products
  end
end

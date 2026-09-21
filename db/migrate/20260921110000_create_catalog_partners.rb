class CreateCatalogPartners < ActiveRecord::Migration[8.1]
  def up
    create_table :catalog_partners do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :name, null: false
      t.string :document_type, null: false
      t.string :document_number, null: false
      t.boolean :customer, null: false, default: false
      t.boolean :supplier, null: false, default: false
      t.string :email
      t.string :phone
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    # document_number is Active Record Encryption ciphertext (ADR 0012),
    # deterministic so this unique index (and a future find-by-document
    # lookup) work at the database level like any other column.
    add_index :catalog_partners, [ :organization_id, :document_number ], unique: true,
      name: "index_catalog_partners_on_organization_id_and_document_number"

    # Lets a future sales_orders.partner_id / purchase_orders.partner_id
    # reference (organization_id, partner_id) as a composite foreign key,
    # the same reason catalog_categories and inventory_warehouses carry
    # this index (see their migrations): row level security does not apply
    # to foreign key checks.
    add_index :catalog_partners, [ :organization_id, :id ], unique: true,
      name: "index_catalog_partners_on_organization_id_and_id"

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE catalog_partners ENABLE ROW LEVEL SECURITY;

        CREATE POLICY catalog_partners_tenant_isolation ON catalog_partners
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :catalog_partners
  end
end

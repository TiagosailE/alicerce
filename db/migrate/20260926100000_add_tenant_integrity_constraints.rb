class AddTenantIntegrityConstraints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Row level security does not apply to foreign key checks, so a plain
  # single-column foreign key accepts an id that exists but belongs to another
  # organization. Every reference between tenant tables therefore points at a
  # composite (organization_id, id) key, as catalog_products.category_id
  # already does (20260920120000). The model layer rejects the same rows
  # first; these are the backstop for a write that bypasses it (insert_all, a
  # data-fix script). Added NOT VALID and validated in the next migration.
  def change
    add_index :catalog_units, [ :organization_id, :id ], unique: true,
      name: "index_catalog_units_on_organization_id_and_id", algorithm: :concurrently
    add_index :catalog_products, [ :organization_id, :id ], unique: true,
      name: "index_catalog_products_on_organization_id_and_id", algorithm: :concurrently

    add_foreign_key :catalog_products, :catalog_units,
      column: [ :organization_id, :stock_unit_id ], primary_key: [ :organization_id, :id ],
      name: "fk_catalog_products_stock_unit_same_organization", validate: false
    add_foreign_key :catalog_unit_conversions, :catalog_units,
      column: [ :organization_id, :purchase_unit_id ], primary_key: [ :organization_id, :id ],
      name: "fk_catalog_unit_conversions_purchase_unit_same_organization", validate: false
    add_foreign_key :catalog_unit_conversions, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_catalog_unit_conversions_product_same_organization", validate: false

    add_check_constraint :catalog_partners, "document_type IN ('cpf', 'cnpj')",
      name: "catalog_partners_document_type_valid", validate: false
    add_check_constraint :catalog_partners, "customer OR supplier",
      name: "catalog_partners_customer_or_supplier", validate: false
  end
end

class ValidateTenantIntegrityConstraints < ActiveRecord::Migration[8.1]
  # Second step of 20260926100000: validating scans the table but only takes
  # a lock that lets reads and writes continue. There is no down: a validated
  # constraint has nothing to undo short of dropping it, which the previous
  # migration's rollback already does.
  def up
    validate_foreign_key :catalog_products, name: "fk_catalog_products_stock_unit_same_organization"
    validate_foreign_key :catalog_unit_conversions, name: "fk_catalog_unit_conversions_purchase_unit_same_organization"
    validate_foreign_key :catalog_unit_conversions, name: "fk_catalog_unit_conversions_product_same_organization"

    validate_check_constraint :catalog_partners, name: "catalog_partners_document_type_valid"
    validate_check_constraint :catalog_partners, name: "catalog_partners_customer_or_supplier"
  end

  def down; end
end

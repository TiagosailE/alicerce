module Inventory
  # One row per product and warehouse: the row that gets locked (ADR 0004)
  # and that holds the quantities and the inventory value (ADR 0006, ADR
  # 0016). Only the inventory commands write it, and only through a row
  # obtained from lock_for, which is the sole place a balance is created.
  class Balance < ApplicationRecord
    include TenantScoped

    belongs_to :product, class_name: "Catalog::Product"
    belongs_to :warehouse, class_name: "Inventory::Warehouse"

    UNIQUE_INDEX = "index_inventory_balances_on_organization_product_and_warehouse".freeze

    # Locks the balances of the given [product_id, warehouse_id] pairs in
    # ascending order, creating the missing ones first with INSERT ... ON
    # CONFLICT DO NOTHING (ADR 0004). Must run inside a transaction, after the
    # documents the command acts on are locked. Every check that depends on
    # these rows happens after this call, on the re-read values it returns.
    def self.lock_for(organization:, pairs:)
      ordered = pairs.uniq.sort
      insert_all(
        ordered.map { |product_id, warehouse_id| { organization_id: organization.id, product_id:, warehouse_id: } },
        unique_by: UNIQUE_INDEX
      )
      ordered.map { |product_id, warehouse_id| where(product_id:, warehouse_id:) }.reduce(:or)
        .order(:product_id, :warehouse_id).lock("FOR NO KEY UPDATE").to_a
    end

    def available = on_hand - reserved
  end
end

class CreatePurchasingOrders < ActiveRecord::Migration[8.1]
  # ADR 0017. The supplier's name and document are copied when the order is
  # created (ADR 0015); the document number is stored encrypted (ADR 0012).
  # total_cents is the sum of the lines' net, stored so no screen adds money.
  def up
    create_table :purchasing_orders do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :number, null: false
      t.bigint :supplier_id, null: false
      t.string :supplier_name, null: false
      t.string :supplier_document_type, null: false
      t.string :supplier_document_number, null: false
      t.string :status, null: false, default: "draft"
      t.string :currency, limit: 3, null: false, default: "BRL"
      t.integer :installments, null: false, default: 1
      t.integer :first_due_days, null: false, default: 30
      t.integer :interval_days, null: false, default: 30
      t.text :note
      t.bigint :total_cents, null: false, default: 0
      t.integer :revision, null: false, default: 0
      t.datetime :approved_at
      t.references :approved_by_user, foreign_key: { to_table: :identity_users }
      t.datetime :cancelled_at
      t.references :cancelled_by_user, foreign_key: { to_table: :identity_users }
      t.references :created_by_user, null: false, foreign_key: { to_table: :identity_users }
      t.timestamps
    end

    add_index :purchasing_orders, [ :organization_id, :number ], unique: true,
      name: "index_purchasing_orders_on_organization_id_and_number"
    add_index :purchasing_orders, [ :organization_id, :id ], unique: true,
      name: "index_purchasing_orders_on_organization_id_and_id"
    add_index :purchasing_orders, [ :organization_id, :supplier_id ]
    add_index :purchasing_orders, [ :organization_id, :status, :number ],
      name: "index_purchasing_orders_on_organization_status_and_number"

    add_foreign_key :purchasing_orders, :catalog_partners,
      column: [ :organization_id, :supplier_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_orders_supplier_same_organization", validate: false

    add_check_constraint :purchasing_orders,
      "status IN ('draft', 'approved', 'partially_received', 'received', 'cancelled')",
      name: "purchasing_orders_status_valid"
    add_check_constraint :purchasing_orders, "installments BETWEEN 1 AND 24", name: "purchasing_orders_installments_range"
    add_check_constraint :purchasing_orders, "first_due_days BETWEEN 0 AND 365", name: "purchasing_orders_first_due_days_range"
    add_check_constraint :purchasing_orders, "interval_days BETWEEN 0 AND 365", name: "purchasing_orders_interval_days_range"
    add_check_constraint :purchasing_orders, "total_cents BETWEEN 0 AND 1000000000000000", name: "purchasing_orders_total_range"
    add_check_constraint :purchasing_orders, "currency = 'BRL'", name: "purchasing_orders_currency_brl"
    add_check_constraint :purchasing_orders, "revision >= 0", name: "purchasing_orders_revision_not_negative"

    safety_assured do
      execute <<~SQL
        ALTER TABLE purchasing_orders ENABLE ROW LEVEL SECURITY;

        CREATE POLICY purchasing_orders_tenant_isolation ON purchasing_orders
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :purchasing_orders
  end
end

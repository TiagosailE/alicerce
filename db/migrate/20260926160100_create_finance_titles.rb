class CreateFinanceTitles < ActiveRecord::Migration[8.1]
  # ADR 0017. A title is what one receipt owes (kind payable); slice 5 adds the
  # receivable that an invoice creates (an invoice_id beside receipt_id, with a
  # check that exactly one is set) and slice 6 the paid states and settlements.
  # The installments always add up to the title's total, by construction
  # (Money.allocate) and by a spec, and none is ever zero.
  def up
    create_table :finance_titles do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :kind, null: false
      t.bigint :partner_id, null: false
      t.string :partner_name, null: false
      t.bigint :receipt_id
      t.bigint :total_cents, null: false
      t.string :currency, limit: 3, null: false, default: "BRL"
      t.string :status, null: false, default: "open"
      t.timestamps
    end

    add_index :finance_titles, [ :organization_id, :id ], unique: true, name: "index_finance_titles_on_organization_id_and_id"
    add_index :finance_titles, :receipt_id, unique: true, where: "receipt_id IS NOT NULL", name: "index_finance_titles_on_receipt_id"
    add_index :finance_titles, [ :organization_id, :kind, :status ]

    add_foreign_key :finance_titles, :catalog_partners,
      column: [ :organization_id, :partner_id ], primary_key: [ :organization_id, :id ],
      name: "fk_finance_titles_partner_same_organization", validate: false
    add_foreign_key :finance_titles, :purchasing_receipts,
      column: [ :organization_id, :receipt_id ], primary_key: [ :organization_id, :id ],
      name: "fk_finance_titles_receipt_same_organization", validate: false

    add_check_constraint :finance_titles, "kind IN ('payable', 'receivable')", name: "finance_titles_kind_valid"
    add_check_constraint :finance_titles, "status IN ('open', 'cancelled')", name: "finance_titles_status_valid"
    add_check_constraint :finance_titles, "total_cents > 0 AND total_cents <= 1000000000000000", name: "finance_titles_total_range"
    add_check_constraint :finance_titles, "currency = 'BRL'", name: "finance_titles_currency_brl"
    add_check_constraint :finance_titles, "kind <> 'payable' OR receipt_id IS NOT NULL", name: "finance_titles_payable_has_a_receipt"

    create_table :finance_installments do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :title_id, null: false
      t.integer :number, null: false
      t.date :due_on, null: false
      t.bigint :amount_cents, null: false
      t.bigint :settled_cents, null: false, default: 0
      t.timestamps
    end

    add_index :finance_installments, [ :title_id, :number ], unique: true, name: "index_finance_installments_on_title_and_number"
    add_index :finance_installments, [ :organization_id, :due_on ], name: "index_finance_installments_on_organization_and_due_on"

    add_foreign_key :finance_installments, :finance_titles,
      column: [ :organization_id, :title_id ], primary_key: [ :organization_id, :id ],
      name: "fk_finance_installments_title_same_organization", validate: false

    add_check_constraint :finance_installments, "number > 0", name: "finance_installments_number_positive"
    add_check_constraint :finance_installments, "amount_cents > 0", name: "finance_installments_amount_positive"
    add_check_constraint :finance_installments, "settled_cents BETWEEN 0 AND amount_cents", name: "finance_installments_settled_within_amount"

    safety_assured do
      execute <<~SQL
        ALTER TABLE finance_titles ENABLE ROW LEVEL SECURITY;
        CREATE POLICY finance_titles_tenant_isolation ON finance_titles
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);

        ALTER TABLE finance_installments ENABLE ROW LEVEL SECURITY;
        CREATE POLICY finance_installments_tenant_isolation ON finance_installments
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :finance_installments
    drop_table :finance_titles
  end
end

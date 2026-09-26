class CreateDocumentCounters < ActiveRecord::Migration[8.1]
  # Sequential numbers per organization and document type (docs/scope.md),
  # taken inside the transaction that creates the document, last in ADR 0004's
  # lock order. The row is locked by the UPDATE that increments it and released
  # at commit, so a rollback returns the number and there are no gaps.
  def up
    create_table :document_counters do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :kind, null: false
      t.bigint :last_value, null: false, default: 0
      t.timestamps
    end

    add_index :document_counters, [ :organization_id, :kind ], unique: true,
      name: "index_document_counters_on_organization_and_kind"
    add_check_constraint :document_counters, "last_value >= 0", name: "document_counters_last_value_not_negative"
    add_check_constraint :document_counters, "kind IN ('purchase_order', 'receipt')", name: "document_counters_kind_valid"

    safety_assured do
      execute <<~SQL
        ALTER TABLE document_counters ENABLE ROW LEVEL SECURITY;

        CREATE POLICY document_counters_tenant_isolation ON document_counters
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :document_counters
  end
end

class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  # ADR 0005: a key is inserted first inside the command transaction and
  # committed with the effect, so a failed attempt leaves nothing behind. No
  # response body is stored, only the status and a reference to the resource,
  # so the table holds no personal data.
  def up
    create_table :idempotency_keys do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.references :user, null: false, foreign_key: { to_table: :identity_users }
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status
      t.string :resource_type
      t.bigint :resource_id
      t.datetime :created_at, null: false
    end

    add_index :idempotency_keys, [ :organization_id, :user_id, :key ], unique: true,
      name: "index_idempotency_keys_on_organization_user_and_key"
    add_index :idempotency_keys, :created_at

    safety_assured do
      execute <<~SQL
        ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;

        CREATE POLICY idempotency_keys_tenant_isolation ON idempotency_keys
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    drop_table :idempotency_keys
  end
end

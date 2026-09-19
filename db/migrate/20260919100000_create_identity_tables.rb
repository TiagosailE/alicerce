class CreateIdentityTables < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_organizations do |t|
      t.string :name, null: false
      t.string :time_zone, null: false, default: "America/Sao_Paulo"
      t.boolean :demo, null: false, default: false
      t.timestamps
    end

    create_table :identity_users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.boolean :demo, null: false, default: false
      t.timestamps
    end
    add_index :identity_users, "lower(email)", unique: true, name: "index_identity_users_on_lower_email"

    create_table :identity_memberships do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.references :user, null: false, foreign_key: { to_table: :identity_users }
      t.string :role, null: false
      t.timestamps
    end
    add_index :identity_memberships, [ :organization_id, :user_id ], unique: true
    add_check_constraint :identity_memberships,
      "role IN ('owner', 'admin', 'purchasing', 'sales', 'finance', 'read_only')",
      name: "identity_memberships_role_valid"

    create_table :identity_sessions do |t|
      t.references :user, null: false, foreign_key: { to_table: :identity_users }
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.string :token_digest, null: false, index: { unique: true }
      t.string :ip
      t.string :user_agent
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
  end
end

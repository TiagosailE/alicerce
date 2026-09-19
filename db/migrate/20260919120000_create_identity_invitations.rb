class CreateIdentityInvitations < ActiveRecord::Migration[8.1]
  def up
    create_table :identity_invitations do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.references :invited_by_user, null: false, foreign_key: { to_table: :identity_users }
      t.references :accepted_by_user, foreign_key: { to_table: :identity_users }
      t.string :email, null: false
      t.string :role, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :identity_invitations, [ :organization_id, :email ]
    add_check_constraint :identity_invitations,
      "role IN ('owner', 'admin', 'purchasing', 'sales', 'finance', 'read_only')",
      name: "identity_invitations_role_valid"

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # safety_assured: enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE identity_invitations ENABLE ROW LEVEL SECURITY;

        CREATE POLICY identity_invitations_tenant_isolation ON identity_invitations
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end

    # ADR 0003: the acceptance endpoint knows no organization until it has
    # read the invitation, so it cannot set the RLS tenant first. This is
    # the one place allowed to read across tenants, and it only ever hands
    # back an organization_id, never a row of identity_invitations itself;
    # Identity::Invitation.find_by_token applies that id as the tenant
    # setting, then loads the row through the ordinary RLS-scoped query.
    # safety_assured: a new function, nothing existing calls yet.
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION invitation_organization_id(target_token_digest varchar) RETURNS bigint
        LANGUAGE sql SECURITY DEFINER AS $$
          SELECT organization_id FROM identity_invitations WHERE token_digest = target_token_digest LIMIT 1;
        $$;

        REVOKE ALL ON FUNCTION invitation_organization_id(varchar) FROM PUBLIC;
      SQL
    end

    # alicerce_app does not exist yet the very first time this migration runs
    # in development or test (see the audit_events migration for why);
    # DatabaseRoles.grant_app_privileges! re-applies the same grant on every
    # boot regardless, so this is not the only place it is enforced, just the
    # first. safety_assured: a conditional grant naming only the function
    # just created above.
    safety_assured do
      execute <<~SQL
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'GRANT EXECUTE ON FUNCTION invitation_organization_id(varchar) TO alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP FUNCTION IF EXISTS invitation_organization_id(varchar);"
    end

    drop_table :identity_invitations
  end
end

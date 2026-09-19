class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :audit_events do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.references :actor_user, null: false, foreign_key: { to_table: :identity_users }
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      # Not "changes": that name collides with ActiveModel::Dirty#changes,
      # which every ActiveRecord instance already defines.
      t.jsonb :field_changes, null: false, default: {}
      t.string :request_id
      t.string :ip_prefix
      t.datetime :created_at, null: false
    end

    add_index :audit_events, [ :organization_id, :created_at ]
    add_index :audit_events, [ :organization_id, :subject_type, :subject_id ]

    # ADR 0003: shared tables, tenant isolation enforced by Postgres too.
    # strong_migrations cannot inspect an execute call; safety_assured
    # because this only enables RLS and adds a policy on a table this same
    # migration just created, nothing existing traffic depends on yet.
    safety_assured do
      execute <<~SQL
        ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;

        CREATE POLICY audit_events_tenant_isolation ON audit_events
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end

    # ADR 0010: append-only, enforced twice. The revoke below stops the app
    # role outright; the trigger stops every role except the table owner,
    # including a future grant that reintroduces the privilege by mistake.
    # Compares against the real table owner rather than the literal name
    # "alicerce_owner": that is who owns it in production (docs/deploy.md),
    # but migrations run as a plain superuser locally, so a hardcoded name
    # would block the SECURITY DEFINER functions below in every dev and
    # test run, since current_user inside one of those is the function's
    # (and here, the table's) owner, not the role that called it.
    # safety_assured: a trigger on the table this migration just created.
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION audit_events_append_only() RETURNS trigger AS $$
        BEGIN
          IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'audit_events') THEN
            RAISE EXCEPTION 'audit_events is append-only: % is not permitted for %', TG_OP, current_user;
          END IF;

          RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER audit_events_append_only
          BEFORE UPDATE OR DELETE ON audit_events
          FOR EACH ROW EXECUTE FUNCTION audit_events_append_only();
      SQL
    end

    # ADR 0010: the only two ways to remove or alter a row, both owned by
    # the owner role so they run with its privileges (bypassing the revoke
    # below and the trigger's role check) regardless of who calls them.
    # safety_assured: new functions, nothing existing calls yet.
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION audit_purge(target_organization_id bigint, purge_before timestamptz) RETURNS bigint
        LANGUAGE plpgsql SECURITY DEFINER AS $$
        DECLARE
          purged_count bigint;
        BEGIN
          DELETE FROM audit_events
          WHERE organization_id = target_organization_id AND created_at < purge_before;

          GET DIAGNOSTICS purged_count = ROW_COUNT;
          RETURN purged_count;
        END;
        $$;

        REVOKE ALL ON FUNCTION audit_purge(bigint, timestamptz) FROM PUBLIC;

        CREATE FUNCTION audit_redact(target_organization_id bigint, target_subject_type varchar, target_subject_id bigint) RETURNS bigint
        LANGUAGE plpgsql SECURITY DEFINER AS $$
        DECLARE
          redacted_count bigint;
        BEGIN
          UPDATE audit_events
          SET field_changes = '{"redacted": true}'::jsonb
          WHERE organization_id = target_organization_id
            AND subject_type = target_subject_type
            AND subject_id = target_subject_id;

          GET DIAGNOSTICS redacted_count = ROW_COUNT;
          RETURN redacted_count;
        END;
        $$;

        REVOKE ALL ON FUNCTION audit_redact(bigint, varchar, bigint) FROM PUBLIC;
      SQL
    end

    # alicerce_app does not exist yet the very first time this migration
    # runs in development or test (lib/tasks/database_roles.rake creates it
    # after db:migrate, since it needs a database to connect to); production
    # always has it already (docs/deploy.md, a manual step before the first
    # deploy). Either way, DatabaseRoles.grant_app_privileges! applies the
    # same revoke and grants again on every boot, so this is not the only
    # place they are enforced, just the first. safety_assured: conditional
    # grant/revoke naming only the table and functions just created above.
    safety_assured do
      execute <<~SQL
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'REVOKE UPDATE, DELETE ON audit_events FROM alicerce_app';
            EXECUTE 'GRANT EXECUTE ON FUNCTION audit_purge(bigint, timestamptz) TO alicerce_app';
            EXECUTE 'GRANT EXECUTE ON FUNCTION audit_redact(bigint, varchar, bigint) TO alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP FUNCTION IF EXISTS audit_redact(bigint, varchar, bigint);
        DROP FUNCTION IF EXISTS audit_purge(bigint, timestamptz);
        DROP TRIGGER IF EXISTS audit_events_append_only ON audit_events;
        DROP FUNCTION IF EXISTS audit_events_append_only();
      SQL
    end

    drop_table :audit_events
  end
end

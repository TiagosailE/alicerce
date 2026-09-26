class HardenInventoryMovements < ActiveRecord::Migration[8.1]
  # Two gaps a security review found in the ledger's immutability, both on the
  # table this slice created, so nothing in production depends on them yet.
  #
  # 1. TRUNCATE is not covered by the row-level UPDATE/DELETE trigger; only the
  #    missing privilege stopped it. A statement trigger now refuses it for
  #    everyone but the table owner.
  # 2. The note is free text in a table nobody can edit, so an erasure request
  #    could never be met. inventory_movement_redact_note is the owner-only way
  #    to blank one note, the same shape as audit_redact (ADR 0010); it runs as
  #    the owner (bypassing the revoke and the trigger's role check) but only
  #    for the organization the caller is working in, so a bug elsewhere cannot
  #    point it at another tenant.
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION inventory_movements_no_truncate() RETURNS trigger AS $$
        BEGIN
          IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'inventory_movements') THEN
            RAISE EXCEPTION 'inventory_movements is append-only: TRUNCATE is not permitted for %', current_user;
          END IF;

          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER inventory_movements_no_truncate
          BEFORE TRUNCATE ON inventory_movements
          FOR EACH STATEMENT EXECUTE FUNCTION inventory_movements_no_truncate();

        CREATE FUNCTION inventory_movement_redact_note(target_organization_id bigint, target_movement_id bigint) RETURNS bigint
        LANGUAGE plpgsql SECURITY DEFINER AS $$
        DECLARE
          redacted_count bigint;
        BEGIN
          IF target_organization_id IS DISTINCT FROM NULLIF(current_setting('app.organization_id', true), '')::bigint THEN
            RAISE EXCEPTION 'inventory_movement_redact_note: not the current organization';
          END IF;

          UPDATE inventory_movements
          SET note = NULL
          WHERE organization_id = target_organization_id AND id = target_movement_id AND note IS NOT NULL;

          GET DIAGNOSTICS redacted_count = ROW_COUNT;
          RETURN redacted_count;
        END;
        $$;

        REVOKE ALL ON FUNCTION inventory_movement_redact_note(bigint, bigint) FROM PUBLIC;

        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'GRANT EXECUTE ON FUNCTION inventory_movement_redact_note(bigint, bigint) TO alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP FUNCTION IF EXISTS inventory_movement_redact_note(bigint, bigint);
        DROP TRIGGER IF EXISTS inventory_movements_no_truncate ON inventory_movements;
        DROP FUNCTION IF EXISTS inventory_movements_no_truncate();
      SQL
    end
  end
end

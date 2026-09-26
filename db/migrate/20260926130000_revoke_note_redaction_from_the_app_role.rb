class RevokeNoteRedactionFromTheAppRole < ActiveRecord::Migration[8.1]
  # inventory_movement_redact_note was documented as owner-only but granted to
  # the application role, and re-granted on every boot. The app role is the one
  # an SQL injection would run as, and nothing in the application calls the
  # function, so it is now really owner-only: erasing a note is an operator's
  # act, until the LGPD slice adds a command that records who did it.
  def up
    safety_assured do
      execute <<~SQL
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'REVOKE EXECUTE ON FUNCTION inventory_movement_redact_note(bigint, bigint) FROM alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'GRANT EXECUTE ON FUNCTION inventory_movement_redact_note(bigint, bigint) TO alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end
end

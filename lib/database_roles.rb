# Creates the application role in development and test and grants it the same
# row privileges production gives alicerce_app, so the test suite can run as a
# role that neither owns the tables nor bypasses row level security (ADR 0003).
# Production roles are created by hand (docs/deploy.md); this never runs there.
module DatabaseRoles
  APP_ROLE = "alicerce_app".freeze
  APP_PASSWORD = "alicerce_app".freeze

  # A migration revokes UPDATE and DELETE from the app role the moment it
  # creates one of these (ADR 0010); the blanket grant below would silently
  # re-add them on every db:prepare unless told to skip these tables. On a
  # first-ever boot the role does not exist yet when that migration runs
  # (this task runs after db:migrate, matching how db:prepare can create the
  # role only once a database exists), so the migration's own revoke and
  # grants are best-effort and this is what actually enforces them.
  APPEND_ONLY_TABLES = %w[audit_events inventory_movements].freeze
  OWNER_ONLY_FUNCTIONS = {
    "audit_purge" => "bigint, timestamptz",
    "audit_redact" => "bigint, varchar, bigint",
    "invitation_organization_id" => "varchar"
  }.freeze

  # Functions only the owner may execute. A migration revokes PUBLIC and the app
  # role, but db/structure.sql omits privileges, so a database loaded from it
  # would keep PostgreSQL's default of EXECUTE for everyone; this is what makes
  # development and test match production (docs/security.md).
  OWNER_EXECUTE_ONLY_FUNCTIONS = {
    "inventory_movement_redact_note" => "bigint, bigint"
  }.freeze

  module_function

  def prepare!(connection)
    raise "DatabaseRoles is for development and test only" if Rails.env.production?

    ensure_app_role!(connection)
    grant_app_privileges!(connection)
  end

  def ensure_app_role!(connection)
    exists = connection.select_value("SELECT 1 FROM pg_roles WHERE rolname = #{connection.quote(APP_ROLE)}")
    return if exists

    connection.execute("CREATE ROLE #{APP_ROLE} LOGIN PASSWORD #{connection.quote(APP_PASSWORD)} NOSUPERUSER NOBYPASSRLS")
  end

  def grant_app_privileges!(connection)
    connection.execute(<<~SQL)
      GRANT USAGE ON SCHEMA public TO #{APP_ROLE};
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{APP_ROLE};
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{APP_ROLE};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{APP_ROLE};
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{APP_ROLE};
    SQL

    revoke_append_only_privileges!(connection)
    grant_owner_only_function_privileges!(connection)
    revoke_owner_execute_only_privileges!(connection)
  end

  def revoke_append_only_privileges!(connection)
    APPEND_ONLY_TABLES.each do |table|
      next unless connection.table_exists?(table)

      connection.execute("REVOKE UPDATE, DELETE ON #{table} FROM #{APP_ROLE}")
    end
  end

  def revoke_owner_execute_only_privileges!(connection)
    OWNER_EXECUTE_ONLY_FUNCTIONS.each do |name, signature|
      next unless connection.select_value("SELECT 1 FROM pg_proc WHERE proname = #{connection.quote(name)}")

      connection.execute("REVOKE ALL ON FUNCTION #{name}(#{signature}) FROM PUBLIC")
      connection.execute("REVOKE ALL ON FUNCTION #{name}(#{signature}) FROM #{APP_ROLE}")
    end
  end

  def grant_owner_only_function_privileges!(connection)
    OWNER_ONLY_FUNCTIONS.each do |name, signature|
      exists = connection.select_value("SELECT 1 FROM pg_proc WHERE proname = #{connection.quote(name)}")
      next unless exists

      connection.execute("GRANT EXECUTE ON FUNCTION #{name}(#{signature}) TO #{APP_ROLE}")
    end
  end

  def app_connection_config(owner_config)
    config = owner_config.merge(username: APP_ROLE, password: APP_PASSWORD)
    # A Unix socket authenticates by OS user (peer auth), which only works for
    # the role matching the current OS user. The app role connects over TCP
    # instead, where Postgres asks for the password we just set.
    config[:host] = "127.0.0.1" if config[:host].to_s.start_with?("/")
    config
  end
end

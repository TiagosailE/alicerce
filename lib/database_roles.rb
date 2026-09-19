# Creates the application role in development and test and grants it the same
# row privileges production gives alicerce_app, so the test suite can run as a
# role that neither owns the tables nor bypasses row level security (ADR 0003).
# Production roles are created by hand (docs/deploy.md); this never runs there.
module DatabaseRoles
  APP_ROLE = "alicerce_app".freeze
  APP_PASSWORD = "alicerce_app".freeze

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

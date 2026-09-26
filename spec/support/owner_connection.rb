require "pg"

# The examples run as the application role (spec/rails_helper.rb). A few things
# can only be proven as the role that owns the tables or as a role with more
# privileges than the app has: that a trigger fires for a role that does hold
# the privilege, that an owner-only function is callable by the owner and by
# nobody else. This opens a plain connection as the owner, outside Active
# Record, for exactly that.
module OwnerConnection
  def with_owner_connection
    config = OWNER_DB_CONFIG
    connection = PG.connect(
      host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password]
    )
    yield connection
  ensure
    connection&.close
  end
end

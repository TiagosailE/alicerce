require "rails_helper"

RSpec.describe "Test harness" do
  it "runs the examples as the application role, not as an owner or superuser" do
    role = ActiveRecord::Base.connection.select_one(<<~SQL)
      SELECT current_user AS name, rolsuper, rolbypassrls
      FROM pg_roles WHERE rolname = current_user
    SQL

    expect(role).to include("name" => DatabaseRoles::APP_ROLE, "rolsuper" => false, "rolbypassrls" => false)
  end

  it "does not let the application role change the schema" do
    expect {
      ActiveRecord::Base.connection.execute("ALTER TABLE identity_users ADD COLUMN probe integer")
    }.to raise_error(ActiveRecord::StatementInvalid, /must be owner/)
  end
end

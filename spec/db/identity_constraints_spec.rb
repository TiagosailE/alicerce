require "rails_helper"

RSpec.describe "Identity constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:membership) { create(:membership) }

  it "rejects a membership role outside the fixed list" do
    expect {
      connection.execute("UPDATE identity_memberships SET role = 'superadmin' WHERE id = #{membership.id}")
    }.to raise_error(ActiveRecord::StatementInvalid, /identity_memberships_role_valid/)
  end

  it "rejects a second membership of the same user in the same organization" do
    expect {
      connection.execute(<<~SQL)
        INSERT INTO identity_memberships (organization_id, user_id, role, created_at, updated_at)
        VALUES (#{membership.organization_id}, #{membership.user_id}, 'sales', now(), now())
      SQL
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects two users whose emails differ only in case" do
    create(:user, email: "rita@canion.example")

    expect {
      connection.execute(<<~SQL)
        INSERT INTO identity_users (email, name, password_digest, created_at, updated_at)
        VALUES ('RITA@canion.example', 'Rita', 'x', now(), now())
      SQL
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

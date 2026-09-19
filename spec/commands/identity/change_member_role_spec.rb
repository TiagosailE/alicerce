require "rails_helper"

RSpec.describe Identity::ChangeMemberRole do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "changes the role and returns the updated membership" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")

    result = described_class.call(membership:, role: "finance", actor:)

    expect(result).to be_success
    expect(result.value.reload.role).to eq("finance")
  end

  it "records a member_role_changed audit event with the previous and new role" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")

    described_class.call(membership:, role: "finance", actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("member_role_changed")
    expect(event.actor).to eq(actor)
    expect(event.field_changes).to eq("role" => { "from" => "sales", "to" => "finance" })
  end

  it "revokes every other session that member holds, in every organization" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")
    _here, here_token = Identity::Session.start!(user: member, organization:, ip: "203.0.113.9", user_agent: "spec")
    other_organization = create(:organization)
    create(:membership, organization: other_organization, user: member, role: "read_only")
    _elsewhere, elsewhere_token = Identity::Session.start!(user: member, organization: other_organization, ip: "203.0.113.9", user_agent: "spec")

    described_class.call(membership:, role: "finance", actor:)

    expect(Identity::Session.count).to eq(0)
  end

  it "keeps the acting session alive when the actor changes their own role" do
    membership = create(:membership, organization:, user: actor, role: "admin")
    acting_session, = Identity::Session.start!(user: actor, organization:, ip: "203.0.113.9", user_agent: "spec")
    other_owner = create(:user)
    create(:membership, organization:, user: other_owner, role: "owner")

    result = described_class.call(membership:, role: "read_only", actor:, acting_session:)

    expect(result).to be_success
    expect(Identity::Session.exists?(acting_session.id)).to be(true)
  end

  it "fails with validation_failed for a role outside the fixed list" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")

    result = described_class.call(membership:, role: "manager", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(membership.reload.role).to eq("sales")
  end

  it "fails with last_owner when demoting the organization's only owner" do
    membership = create(:membership, organization:, user: create(:user), role: "owner")

    result = described_class.call(membership:, role: "admin", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:last_owner)
    expect(membership.reload.role).to eq("owner")
  end

  it "allows demoting an owner when another owner remains" do
    membership = create(:membership, organization:, user: create(:user), role: "owner")
    create(:membership, organization:, user: create(:user), role: "owner")

    result = described_class.call(membership:, role: "admin", actor:)

    expect(result).to be_success
    expect(membership.reload.role).to eq("admin")
  end
end

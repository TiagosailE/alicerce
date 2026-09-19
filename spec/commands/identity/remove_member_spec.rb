require "rails_helper"

RSpec.describe Identity::RemoveMember do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "removes the membership" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")

    result = described_class.call(membership:, actor:)

    expect(result).to be_success
    expect(Identity::Membership.exists?(membership.id)).to be(false)
  end

  it "records a member_removed audit event with the role the member held" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")

    described_class.call(membership:, actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("member_removed")
    expect(event.actor).to eq(actor)
    expect(event.field_changes).to eq("role" => "sales")
  end

  it "revokes that member's sessions in this organization but not in another one" do
    member = create(:user)
    membership = create(:membership, organization:, user: member, role: "sales")
    Identity::Session.start!(user: member, organization:, ip: "203.0.113.9", user_agent: "spec")
    other_organization = create(:organization)
    create(:membership, organization: other_organization, user: member, role: "read_only")
    elsewhere, = Identity::Session.start!(user: member, organization: other_organization, ip: "203.0.113.9", user_agent: "spec")

    described_class.call(membership:, actor:)

    expect(Identity::Session.exists?(elsewhere.id)).to be(true)
    expect(Identity::Session.where(user: member, organization:)).to be_empty
  end

  it "fails with last_owner when removing the organization's only owner" do
    membership = create(:membership, organization:, user: create(:user), role: "owner")

    result = described_class.call(membership:, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:last_owner)
    expect(Identity::Membership.exists?(membership.id)).to be(true)
  end

  it "allows removing an owner when another owner remains" do
    membership = create(:membership, organization:, user: create(:user), role: "owner")
    create(:membership, organization:, user: create(:user), role: "owner")

    result = described_class.call(membership:, actor:)

    expect(result).to be_success
    expect(Identity::Membership.exists?(membership.id)).to be(false)
  end
end

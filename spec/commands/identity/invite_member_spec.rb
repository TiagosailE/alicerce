require "rails_helper"

RSpec.describe Identity::InviteMember do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "issues an invitation and its raw token" do
    result = described_class.call(organization:, email: "nova@alicerce.example", role: "sales", actor:)

    expect(result).to be_success
    invitation = result.value[:invitation]
    expect(invitation).to be_persisted
    expect(invitation.email).to eq("nova@alicerce.example")
    expect(invitation.role).to eq("sales")
    expect(invitation.invited_by).to eq(actor)
    expect(invitation.token_digest).to eq(Identity::Invitation.digest(result.value[:token]))
  end

  it "records an audit event with the email redacted" do
    described_class.call(organization:, email: "nova@alicerce.example", role: "sales", actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("invitation_sent")
    expect(event.actor).to eq(actor)
    expect(event.field_changes).to eq("email" => "changed", "role" => "sales")
  end

  it "fails with validation_failed for a role outside the fixed list" do
    result = described_class.call(organization:, email: "nova@alicerce.example", role: "manager", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(result.details[:fields]["role"]).to include("inclusion")
    expect(Identity::Invitation.count).to eq(0)
  end

  it "fails with validation_failed for a malformed email" do
    result = described_class.call(organization:, email: "not-an-email", role: "sales", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(result.details[:fields]["email"]).to include("invalid")
  end

  it "fails with already_member when the email already belongs to the organization" do
    member = create(:user, email: "ja-e-membro@alicerce.example")
    create(:membership, organization:, user: member, role: "read_only")

    result = described_class.call(organization:, email: "ja-e-membro@alicerce.example", role: "sales", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:already_member)
    expect(Identity::Invitation.count).to eq(0)
  end

  it "fails with owner_required when a non-owner actor invites someone as owner" do
    create(:membership, organization:, user: actor, role: "admin")

    result = described_class.call(organization:, email: "nova@alicerce.example", role: "owner", actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:owner_required)
    expect(Identity::Invitation.count).to eq(0)
  end

  it "allows an owner actor to invite someone as owner" do
    create(:membership, organization:, user: actor, role: "owner")

    result = described_class.call(organization:, email: "nova@alicerce.example", role: "owner", actor:)

    expect(result).to be_success
    expect(result.value[:invitation].role).to eq("owner")
  end
end

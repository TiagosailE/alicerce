require "rails_helper"

RSpec.describe Identity::RevokeInvitation do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "destroys the invitation" do
    invitation = create(:invitation, organization:, invited_by: actor)

    result = described_class.call(invitation:, actor:)

    expect(result).to be_success
    expect(Identity::Invitation.exists?(invitation.id)).to be(false)
  end

  it "records an invitation_revoked audit event with the email redacted" do
    invitation = create(:invitation, organization:, invited_by: actor, role: "sales")

    described_class.call(invitation:, actor:)

    event = Audit::Event.sole
    expect(event.action).to eq("invitation_revoked")
    expect(event.actor).to eq(actor)
    expect(event.field_changes).to eq("email" => "changed", "role" => "sales")
  end

  it "fails with already_accepted when the invitation was already accepted, leaving it in place" do
    invitation = create(:invitation, organization:, invited_by: actor, accepted_at: Time.current, accepted_by: create(:user))

    result = described_class.call(invitation:, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:already_accepted)
    expect(Identity::Invitation.exists?(invitation.id)).to be(true)
  end

  it "fails with already_accepted for an expired invitation that was accepted right before it expired" do
    invitation = create(:invitation, organization:, invited_by: actor, expires_at: 1.minute.ago, accepted_at: 2.minutes.ago, accepted_by: create(:user))

    result = described_class.call(invitation:, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:already_accepted)
  end

  it "revokes an expired but still unaccepted invitation" do
    invitation = create(:invitation, organization:, invited_by: actor, expires_at: 1.minute.ago)

    result = described_class.call(invitation:, actor:)

    expect(result).to be_success
    expect(Identity::Invitation.exists?(invitation.id)).to be(false)
  end
end

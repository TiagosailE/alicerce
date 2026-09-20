require "rails_helper"

RSpec.describe Identity::AcceptInvitation do
  let(:organization) { create(:organization) }
  let(:inviter) { create(:user) }

  def invitation_for(email:, role: "sales")
    set_current_tenant(organization)
    create(:invitation, organization:, invited_by: inviter, email:, role:)
  end

  it "fails with invalid_token when there is no invitation" do
    result = described_class.call(invitation: nil, name: "Nova Pessoa", password: "senha-de-teste-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_token)
  end

  context "when the invited email has no account yet" do
    let(:invitation) { invitation_for(email: "nova@alicerce.example") }

    it "registers the account and creates a membership at the invited role" do
      result = described_class.call(invitation:, name: "Nova Pessoa", password: "senha-de-teste-longa")

      expect(result).to be_success
      user = result.value[:user]
      membership = result.value[:membership]
      expect(user).to be_persisted
      expect(user.email).to eq("nova@alicerce.example")
      expect(user.name).to eq("Nova Pessoa")
      expect(membership.organization).to eq(organization)
      expect(membership.role).to eq("sales")
      expect(membership.user).to eq(user)
    end

    it "marks the invitation accepted" do
      result = described_class.call(invitation:, name: "Nova Pessoa", password: "senha-de-teste-longa")

      invitation.reload
      expect(invitation.accepted_at).to be_present
      expect(invitation.accepted_by).to eq(result.value[:user])
    end

    it "records a member_joined audit event" do
      result = described_class.call(invitation:, name: "Nova Pessoa", password: "senha-de-teste-longa")

      event = Audit::Event.sole
      expect(event.action).to eq("member_joined")
      expect(event.actor).to eq(result.value[:user])
      expect(event.field_changes).to eq("role" => "sales")
    end

    it "fails with validation_failed when the name is missing" do
      result = described_class.call(invitation:, name: "", password: "senha-de-teste-longa")

      expect(result).not_to be_success
      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]["name"]).to include("blank")
      expect(Identity::Membership.count).to eq(0)
    end

    it "fails with validation_failed when the password is missing" do
      result = described_class.call(invitation:, name: "Nova Pessoa", password: "")

      expect(result).not_to be_success
      expect(result.error).to eq(:validation_failed)
      expect(Identity::Membership.count).to eq(0)
    end
  end

  context "when the invited email already has an account in another organization" do
    let!(:existing_user) { create(:user, email: "gente@alicerce.example") }
    let(:invitation) { invitation_for(email: "gente@alicerce.example", role: "finance") }

    it "joins the existing account without needing a name or password" do
      invitation # build it, and the inviter it depends on, before measuring the count below
      result = nil
      expect { result = described_class.call(invitation:, name: nil, password: nil) }.not_to change(Identity::User, :count)

      expect(result).to be_success
      expect(result.value[:user]).to eq(existing_user)
      expect(result.value[:membership].role).to eq("finance")
    end

    it "fails with already_member when that account already belongs to this organization" do
      set_current_tenant(organization)
      create(:membership, organization:, user: existing_user, role: "read_only")

      result = described_class.call(invitation:, name: nil, password: nil)

      expect(result).not_to be_success
      expect(result.error).to eq(:already_member)
    end
  end

  it "fails with invalid_token instead of raising when the invitation was already accepted (a concurrent replay)" do
    invitation = invitation_for(email: "nova@alicerce.example")
    invitation.update!(accepted_at: Time.current, accepted_by: create(:user))

    result = described_class.call(invitation:, name: "Nova Pessoa", password: "senha-de-teste-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_token)
  end
end

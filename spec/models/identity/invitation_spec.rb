require "rails_helper"

RSpec.describe Identity::Invitation do
  let(:organization) { create(:organization) }

  def build_invitation(**attrs)
    set_current_tenant(organization)
    token = SecureRandom.urlsafe_base64(32)
    invitation = create(:invitation, organization:, token_digest: Identity::Invitation.digest(token), **attrs)
    [ invitation, token ]
  end

  it "downcases and strips the email" do
    set_current_tenant(organization)
    invitation = create(:invitation, organization:, email: "  Pessoa@Exemplo.com ")

    expect(invitation.email).to eq("pessoa@exemplo.com")
  end

  it "rejects a role outside the fixed list" do
    set_current_tenant(organization)
    invitation = build(:invitation, organization:, role: "manager")

    expect(invitation).not_to be_valid
    expect(invitation.errors.of_kind?(:role, :inclusion)).to be(true)
  end

  describe ".find_by_token" do
    it "returns nil for a blank token" do
      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token("")).to be_nil
    end

    it "returns nil for a token that matches no invitation" do
      expect(described_class.find_by_token("not-a-real-token")).to be_nil
    end

    it "finds the invitation and establishes the tenant setting for it" do
      invitation, token = build_invitation
      Current.organization = nil
      TenantSetting.clear!

      found = described_class.find_by_token(token)

      expect(found).to eq(invitation)
      expect(Current.organization).to eq(organization)
    end

    it "returns nil for an expired invitation" do
      _invitation, token = build_invitation(expires_at: 1.minute.ago)

      expect(described_class.find_by_token(token)).to be_nil
    end

    it "returns nil for an already accepted invitation" do
      _invitation, token = build_invitation(accepted_at: 1.minute.ago)

      expect(described_class.find_by_token(token)).to be_nil
    end
  end

  describe "#expired?" do
    it "is true once now reaches expires_at" do
      invitation, _token = build_invitation(expires_at: 10.minutes.from_now)

      expect(invitation.expired?(5.minutes.from_now)).to be(false)
      expect(invitation.expired?(10.minutes.from_now)).to be(true)
      expect(invitation.expired?(15.minutes.from_now)).to be(true)
    end
  end

  describe "#accepted?" do
    it "is true only once accepted_at is set" do
      invitation, _token = build_invitation
      expect(invitation.accepted?).to be(false)

      invitation.update!(accepted_at: Time.current, accepted_by: create(:user))
      expect(invitation.accepted?).to be(true)
    end
  end

  describe ".pending" do
    it "excludes accepted and expired invitations" do
      pending_invitation, = build_invitation
      _accepted, = build_invitation(accepted_at: Time.current, accepted_by: create(:user))
      _expired, = build_invitation(expires_at: 1.minute.ago)

      expect(described_class.pending).to eq([ pending_invitation ])
    end
  end
end

require "rails_helper"

RSpec.describe "Identity invitations constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_invitation(organization)
    set_current_tenant(organization)
    token = SecureRandom.urlsafe_base64(32)
    invitation = create(:invitation, organization:, token_digest: Identity::Invitation.digest(token))
    [ invitation, token ]
  end

  it "hides another organization's invitation from a plain query" do
    invitation, _token = create_invitation(organization)

    set_current_tenant(other_organization)
    expect(connection.select_value("SELECT count(*) FROM identity_invitations WHERE id = #{invitation.id}").to_i).to eq(0)
  end

  it "refuses to insert a row for another organization" do
    inviter = create(:user)
    set_current_tenant(other_organization)

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO identity_invitations (organization_id, invited_by_user_id, email, role, token_digest, expires_at, created_at, updated_at)
          VALUES (#{organization.id}, #{inviter.id}, 'invasor@alicerce.example', 'sales', 'x', now() + interval '1 day', now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end

  describe "invitation_organization_id" do
    it "returns the organization id for a known token digest, regardless of the current tenant" do
      invitation, token = create_invitation(organization)
      digest = Identity::Invitation.digest(token)

      set_current_tenant(other_organization)
      result = connection.select_value("SELECT invitation_organization_id(#{connection.quote(digest)})")

      expect(result.to_i).to eq(invitation.organization_id)
    end

    it "returns null for an unknown token digest" do
      set_current_tenant(organization)

      expect(connection.select_value("SELECT invitation_organization_id('unknown')")).to be_nil
    end
  end
end

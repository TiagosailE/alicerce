require "rails_helper"

RSpec.describe "concurrent revocation and acceptance of the same invitation" do
  # Real threads and committed rows: the race only exists across separate
  # Postgres transactions actually overlapping, not the connection RSpec
  # pins for transactional fixtures.
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  after do
    Identity::Membership.where(organization_id: @organization.id).delete_all
  end

  it "lets exactly one side win; the other fails cleanly instead of raising" do
    @organization = create(:organization)
    inviter = create(:user, email: "convidante-#{SecureRandom.hex(8)}@alicerce.example")
    revoker = create(:user, email: "revogadora-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    create(:membership, organization: @organization, user: revoker, role: "owner")
    invitation = create(:invitation, organization: @organization, invited_by: inviter)

    results = run_concurrently(
      -> {
        set_current_tenant(@organization)
        Identity::AcceptInvitation.call(invitation:, name: "Pessoa Convidada", password: "senha-de-teste-longa")
      },
      -> {
        set_current_tenant(@organization)
        Identity::RevokeInvitation.call(invitation:, actor: revoker)
      }
    )

    accept_result, revoke_result = results

    if accept_result.success?
      expect(revoke_result).not_to be_success
      expect(revoke_result.error).to eq(:already_accepted)
      set_current_tenant(@organization)
      expect(Identity::Invitation.exists?(invitation.id)).to be(true)
    else
      expect(accept_result.error).to eq(:invalid_token)
      expect(revoke_result).to be_success
      set_current_tenant(@organization)
      expect(Identity::Invitation.exists?(invitation.id)).to be(false)
    end
  end
end

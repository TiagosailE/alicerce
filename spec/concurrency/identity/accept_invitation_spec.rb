require "rails_helper"

RSpec.describe "concurrent acceptance of two invitations to the same new email" do
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

  # Memberships are ordinary rows; the organizations, the invited-by user
  # and the audit events this test commits are permanent leftovers, same
  # reasoning as spec/concurrency/identity/owner_removal_spec.rb.
  after do
    Identity::Membership.where(organization_id: [ @organization_a.id, @organization_b.id ]).delete_all
  end

  it "lets exactly one racing acceptance create the account; the other joins the same one" do
    @organization_a = create(:organization)
    @organization_b = create(:organization)
    inviter = create(:user, email: "convidante-#{SecureRandom.hex(8)}@alicerce.example")
    email = "nova-#{SecureRandom.hex(8)}@alicerce.example"

    set_current_tenant(@organization_a)
    invitation_a = create(:invitation, organization: @organization_a, invited_by: inviter, email:, role: "sales")
    set_current_tenant(@organization_b)
    invitation_b = create(:invitation, organization: @organization_b, invited_by: inviter, email:, role: "finance")

    results = run_concurrently(
      -> {
        set_current_tenant(@organization_a)
        Identity::AcceptInvitation.call(invitation: invitation_a, name: "Pessoa A", password: "senha-de-teste-longa")
      },
      -> {
        set_current_tenant(@organization_b)
        Identity::AcceptInvitation.call(invitation: invitation_b, name: "Pessoa B", password: "senha-de-teste-longa")
      }
    )

    # Both invitations are for different organizations, so both acceptances
    # succeed; the point under test is that they end up sharing one account
    # instead of one of them raising RecordNotUnique (see AcceptInvitation).
    expect(results).to all(be_success)
    user_ids = results.map { |result| result.value[:user].id }.uniq
    expect(user_ids.size).to eq(1)
    expect(Identity::User.where("lower(email) = ?", email.downcase).count).to eq(1)
  end
end

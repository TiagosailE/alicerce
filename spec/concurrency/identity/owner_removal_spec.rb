require "rails_helper"

RSpec.describe "concurrent removal of an organization's owners" do
  # Real threads and committed rows, not the connection RSpec pins for
  # transactional fixtures: the race this proves safe only exists across
  # separate Postgres transactions actually overlapping in time.
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # Membership is an ordinary row; the organization, the two users and the
  # audit events this test commits are not cleaned up: audit_events is
  # append-only for every role but the owner (ADR 0010), by design, even in
  # a test that runs as the app role, and it references both the
  # organization and its actor users by a real foreign key, so neither can
  # be deleted afterward. The users get a random email precisely so a later
  # run's factory sequence (which restarts at 1 in a fresh process) never
  # collides with one of these permanent leftovers.
  after do
    Identity::Membership.where(organization_id: @organization.id).delete_all
  end

  it "never leaves the organization with zero owners when two owners remove each other at once" do
    @organization = create(:organization)
    @owner_a = create(:user, email: "owner-a-#{SecureRandom.hex(8)}@alicerce.example")
    @owner_b = create(:user, email: "owner-b-#{SecureRandom.hex(8)}@alicerce.example")
    membership_a = create(:membership, organization: @organization, user: @owner_a, role: "owner")
    membership_b = create(:membership, organization: @organization, user: @owner_b, role: "owner")

    results = run_concurrently(
      -> {
        set_current_tenant(@organization)
        Identity::RemoveMember.call(membership: membership_b, actor: @owner_a)
      },
      -> {
        set_current_tenant(@organization)
        Identity::RemoveMember.call(membership: membership_a, actor: @owner_b)
      }
    )

    # Exactly one of the two removals must win; the other is rejected as
    # :last_owner (it lost the row lock race, see RemoveMember) or, when
    # scheduling has it check after the other already committed,
    # :owner_required (it is no longer a member at all by then). Either way
    # the organization is left with exactly one owner, never zero, and
    # neither call raises.
    remaining_owners = Identity::Membership.where(organization: @organization, role: "owner")
    expect(remaining_owners.count).to eq(1)
    expect(results.map(&:success?)).to contain_exactly(true, false)
    expect(results.reject(&:success?).sole.error).to be_in(%i[last_owner owner_required])
  end
end

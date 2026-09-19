module Identity
  # Removes a member from the organization. Deletes every session that
  # member holds in this organization right away: sessions are not
  # re-checked against membership on every request, so this is what
  # actually ends access before natural expiry, not only its audit trail.
  # Sessions of theirs in other organizations are unaffected.
  #
  # Error codes: :last_owner (would leave the organization with no owner).
  class RemoveMember
    def self.call(...) = new(...).call

    def initialize(membership:, actor:)
      @membership = membership
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        return Result.failure(:last_owner) if last_owner?

        role = @membership.role
        user = @membership.user
        organization = @membership.organization
        @membership.destroy!
        Identity::Session.revoke_others_for!(user, organization:)
        Audit.record("member_removed", @membership, actor: @actor, changes: { role: })

        Result.success(true)
      end
    end

    private
      def last_owner?
        @membership.role == "owner" && @membership.organization.memberships.where(role: "owner").count <= 1
      end
  end
end

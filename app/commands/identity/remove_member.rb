module Identity
  # Removes a member from the organization. Deletes every session that
  # member holds in this organization right away: sessions are not
  # re-checked against membership on every request, so this is what
  # actually ends access before natural expiry, not only its audit trail.
  # Sessions of theirs in other organizations are unaffected.
  #
  # Error codes: :owner_required (only an owner may remove an owner),
  # :last_owner (would leave the organization with no owner),
  # :conflict_retry (lock wait timed out or deadlocked, safe to retry).
  class RemoveMember
    def self.call(...) = new(...).call

    def initialize(membership:, actor:)
      @membership = membership
      @actor = actor
    end

    def call
      return Result.failure(:owner_required) if removing_owner_as_non_owner?

      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        organization = Identity::Organization.lock.find(@membership.organization_id)
        return Result.failure(:last_owner) if last_owner?(organization)

        role = @membership.role
        user = @membership.user
        @membership.destroy!
        Identity::Session.revoke_others_for!(user, organization:)
        Audit.record("member_removed", @membership, actor: @actor, changes: { role: })

        Result.success(true)
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end

    private
      # MembershipPolicy already limited this to owner and admin; an admin
      # must still never remove an owner, same reasoning as ChangeMemberRole.
      def removing_owner_as_non_owner?
        @membership.role == "owner" && @actor.membership_in(@membership.organization)&.role != "owner"
      end

      # Locks the organization row first: see ChangeMemberRole for why an
      # unlocked count lets two concurrent requests both leave with "another
      # owner remains" true and still end the organization with zero.
      def last_owner?(organization)
        @membership.role == "owner" && organization.memberships.where(role: "owner").count <= 1
      end
  end
end

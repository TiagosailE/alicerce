module Identity
  # Cancels a still-pending invitation. The policy already limited this to
  # owner and admin, demo users excluded (Identity::Capabilities.manage_members?).
  # Unlike ChangeMemberRole and RemoveMember, this needs no owner_required
  # guard: cancelling an offer, even one for the owner role, grants or
  # removes nothing, it only takes an option off the table.
  #
  # Error codes: :already_accepted (the invitation became a membership
  # before this ran; nothing left to cancel), :conflict_retry (lock wait
  # timed out or deadlocked, safe to retry).
  class RevokeInvitation
    def self.call(...) = new(...).call

    def initialize(invitation:, actor:)
      @invitation = invitation
      @actor = actor
    end

    def call
      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        # Locked and rechecked here, not trusted from the @invitation the
        # caller looked up: a revocation racing AcceptInvitation on the same
        # token must not destroy the row once acceptance already committed
        # it as a membership's history (same discipline as AcceptInvitation
        # locking against a second acceptance, and the same ADR 0004
        # lock_timeout/conflict_retry discipline every pessimistic lock in
        # this codebase follows, since either side of this race can hang or
        # deadlock against the other locking the same row).
        invitation = Identity::Invitation.lock.find(@invitation.id)
        return Result.failure(:already_accepted) if invitation.accepted?

        invitation.destroy!
        Audit.record("invitation_revoked", invitation, actor: @actor, changes: { email: "changed", role: invitation.role })

        Result.success(true)
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end
  end
end

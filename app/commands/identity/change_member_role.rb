module Identity
  # Changes an existing member's role. Revokes every other session that
  # member holds, in every organization (ADR 0007): a role determines what
  # a session is allowed to do, so a stale one is treated the same as a
  # stale password.
  #
  # Error codes: :validation_failed (not a real role), :owner_required
  # (only an owner may grant the owner role or touch an existing owner's
  # membership), :last_owner (would leave the organization with no owner),
  # :conflict_retry (lock wait timed out or deadlocked, safe to retry).
  class ChangeMemberRole
    def self.call(...) = new(...).call

    def initialize(membership:, role:, actor:, acting_session: nil)
      @membership = membership
      @role = role
      @actor = actor
      @acting_session = acting_session
    end

    def call
      return Result.failure(:validation_failed, fields: { "role" => [ "inclusion" ] }) unless Identity::Membership::ROLES.include?(@role)
      return Result.failure(:owner_required) unless permitted_transition?

      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        organization = Identity::Organization.lock.find(@membership.organization_id)
        return Result.failure(:last_owner) if demoting_last_owner?(organization)

        previous_role = @membership.role
        @membership.update!(role: @role)
        Identity::Session.revoke_others_for!(@membership.user, except: @acting_session)
        Audit.record("member_role_changed", @membership, actor: @actor, changes: { role: { from: previous_role, to: @role } })

        Result.success(@membership)
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end

    private
      # MembershipPolicy already limited this to owner and admin; an admin
      # must still never grant the owner role or change an existing owner's
      # role, or any admin could self-promote and dethrone every real owner.
      def permitted_transition?
        return true if @actor.membership_in(@membership.organization)&.role == "owner"

        @membership.role != "owner" && @role != "owner"
      end

      # Locks the organization row first so two concurrent role changes (or
      # a role change racing a removal, see RemoveMember) cannot both count
      # the same owners before either one commits. This is a new, isolated
      # lock scope, not a position in ADR 0004's order: nothing else in the
      # app locks identity_organizations, so it cannot deadlock against a
      # document, balance or title lock, but it still takes ADR 0004's
      # lock_timeout and conflict_retry discipline (the fix above), since
      # any pessimistic lock can hang or deadlock against another instance
      # of itself.
      def demoting_last_owner?(organization)
        return false unless @membership.role == "owner" && @role != "owner"

        organization.memberships.where(role: "owner").count <= 1
      end
  end
end

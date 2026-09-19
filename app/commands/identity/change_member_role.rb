module Identity
  # Changes an existing member's role. Revokes every other session that
  # member holds, in every organization (ADR 0007): a role determines what
  # a session is allowed to do, so a stale one is treated the same as a
  # stale password.
  #
  # Error codes: :validation_failed (not a real role),
  # :last_owner (would leave the organization with no owner).
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

      ApplicationRecord.transaction do
        return Result.failure(:last_owner) if demoting_last_owner?

        previous_role = @membership.role
        @membership.update!(role: @role)
        Identity::Session.revoke_others_for!(@membership.user, except: @acting_session)
        Audit.record("member_role_changed", @membership, actor: @actor, changes: { role: { from: previous_role, to: @role } })

        Result.success(@membership)
      end
    end

    private
      def demoting_last_owner?
        return false unless @membership.role == "owner" && @role != "owner"

        @membership.organization.memberships.where(role: "owner").count <= 1
      end
  end
end

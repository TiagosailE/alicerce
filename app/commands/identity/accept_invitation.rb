module Identity
  # Turns a pending invitation into a membership, for someone signed into no
  # organization yet (ADR 0003). Joins an existing account when the
  # invited email already has one (anywhere; the data model allows a user
  # in several organizations), registers a new one otherwise. Holding the
  # token is itself the proof of owning that email (ADR 0007): it is
  # unguessable and only ever leaves the server by being sent there.
  #
  # Error codes: :invalid_token (unknown, expired or already accepted, not
  # distinguished so a guess cannot tell which), :validation_failed (a new
  # account needs name and password), :already_member, :conflict_retry
  # (lock wait timed out or deadlocked, safe to retry).
  class AcceptInvitation
    def self.call(...) = new(...).call

    def initialize(invitation:, name:, password:)
      @invitation = invitation
      @name = name
      @password = password
    end

    def call
      return Result.failure(:invalid_token) unless @invitation

      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        # Locked and rechecked here, not trusted from the @invitation the
        # caller looked up: two concurrent acceptances of the same token
        # (a double submit, or a client retry) would otherwise both read
        # accepted_at as nil and race each other into the unique index on
        # (organization_id, user_id), raising instead of failing cleanly.
        # find_by, not find: a RevokeInvitation racing this same token can
        # destroy the row between the caller's lookup and this lock, which
        # must fail the same as any other invalid token, not raise
        # RecordNotFound out of a command. Same ADR 0004 lock_timeout and
        # conflict_retry discipline as every other pessimistic lock in this
        # codebase, since either side of that race can hang against the
        # other locking this same row.
        invitation = Identity::Invitation.lock.find_by(id: @invitation.id)
        return Result.failure(:invalid_token) if invitation.nil? || invitation.accepted? || invitation.expired?

        user = find_or_create_user(invitation)
        return Result.invalid(user) if user.errors.any?

        return Result.failure(:already_member) if user.membership_in(invitation.organization).present?

        membership = Identity::Membership.create!(organization: invitation.organization, user:, role: invitation.role)
        invitation.update!(accepted_at: Time.current, accepted_by: user)
        Audit.record("member_joined", membership, actor: user, changes: { role: membership.role })

        Result.success(user:, membership:)
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end

    private
      # Two different invitations to the same not-yet-registered email
      # (from the same organization by mistake, or from two organizations
      # at once) accepted at the same time both miss the check above and
      # race the unique index on identity_users.email. The insert runs in
      # its own savepoint, not the surrounding transaction, so losing that
      # race does not abort the invitation and membership work still to
      # come: the loser simply falls back to the winner's now-committed
      # account, exactly like the already-has-an-account path below.
      def find_or_create_user(invitation)
        existing = Identity::User.find_by(email: invitation.email)
        return existing if existing

        user = build_user(invitation)
        ApplicationRecord.transaction(requires_new: true) { user.save! }
        user
      rescue ActiveRecord::RecordInvalid
        user
      rescue ActiveRecord::RecordNotUnique
        Identity::User.find_by!(email: invitation.email)
      end

      def build_user(invitation)
        Identity::User.new(email: invitation.email, name: @name, password: @password)
      end
  end
end

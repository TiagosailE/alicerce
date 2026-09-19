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
  # account needs name and password), :already_member.
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
        user = Identity::User.find_by(email: @invitation.email) || build_user
        return Result.invalid(user) if user.new_record? && !user.save

        return Result.failure(:already_member) if user.membership_in(@invitation.organization).present?

        membership = Identity::Membership.create!(organization: @invitation.organization, user:, role: @invitation.role)
        @invitation.update!(accepted_at: Time.current, accepted_by: user)
        Audit.record("member_joined", membership, actor: user, changes: { role: membership.role })

        Result.success(user:, membership:)
      end
    end

    private
      def build_user
        Identity::User.new(email: @invitation.email, name: @name, password: @password)
      end
  end
end

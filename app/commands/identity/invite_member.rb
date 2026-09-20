module Identity
  # Creates a pending membership offer (ADR 0003). The policy already
  # limited this to owner and admin, demo users excluded
  # (Identity::Capabilities.manage_members?), before this ever runs.
  #
  # Error codes: :validation_failed (bad email or role), :owner_required
  # (only an owner may invite someone as owner),
  # :already_member (that email already belongs to this organization).
  class InviteMember
    def self.call(...) = new(...).call

    def initialize(organization:, email:, role:, actor:)
      @organization = organization
      @email = email
      @role = role
      @actor = actor
    end

    def call
      return Result.failure(:owner_required) if @role == "owner" && !actor_is_owner?

      ApplicationRecord.transaction do
        return Result.failure(:already_member) if already_member?

        token = SecureRandom.urlsafe_base64(32)
        invitation = Identity::Invitation.new(
          organization: @organization, email: @email, role: @role, invited_by: @actor,
          token_digest: Identity::Invitation.digest(token),
          expires_at: Time.current + Identity::Invitation::EXPIRY
        )
        return Result.invalid(invitation) unless invitation.save

        Audit.record("invitation_sent", invitation, actor: @actor, changes: { email: "changed", role: invitation.role })
        Result.success(invitation:, token:)
      end
    end

    private
      # Without this, an admin could invite a fresh address as owner and
      # accept it themselves, the same escalation ChangeMemberRole guards
      # against on the promotion side.
      def actor_is_owner?
        @actor.membership_in(@organization)&.role == "owner"
      end

      def already_member?
        user = Identity::User.find_by(email: @email)
        user.present? && user.membership_in(@organization).present?
      end
  end
end

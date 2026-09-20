module Identity
  # A still-open invitation as seen by the members screen: who it was sent
  # to, at which role, by whom, and when it stops being acceptable. No
  # token: only its digest survives past the response that created it.
  class PendingInvitationSerializer
    def initialize(invitation)
      @invitation = invitation
    end

    def as_json
      {
        id: @invitation.id,
        email: @invitation.email,
        role: @invitation.role,
        invited_by: UserSerializer.new(@invitation.invited_by).as_json,
        expires_at: @invitation.expires_at.iso8601
      }
    end
  end
end

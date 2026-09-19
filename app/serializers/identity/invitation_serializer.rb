module Identity
  # The response to issuing an invitation. token is the raw value, shown
  # only this once (only its digest is stored); until Brevo delivery lands
  # (slice 1, PR 6) this is how the demo hands out an invitation link at all
  # (ADR 0002).
  class InvitationSerializer
    def initialize(invitation, token:)
      @invitation = invitation
      @token = token
    end

    def as_json
      { id: @invitation.id, email: @invitation.email, role: @invitation.role, expires_at: @invitation.expires_at.iso8601, token: @token }
    end
  end
end

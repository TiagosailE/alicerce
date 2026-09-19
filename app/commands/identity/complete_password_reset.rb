module Identity
  # Completes a password reset (ADR 0007): the raw token proves the visitor
  # controls that address, the same way an invitation token does (ADR
  # 0003). Never distinguishes an unknown, expired, wrong or demo-account
  # token, so a guess cannot tell which (:invalid_token in every case).
  # Starts no session (the completion request carries no organization to
  # sign into); the caller signs in afterwards through POST /session.
  #
  # No organization is known here, so this cannot be an audit event (ADR
  # 0010: audit_events is tenant scoped); it is a structured log instead,
  # the same reasoning ADR 0010 already applies to failed sign-ins.
  #
  # Error codes: :invalid_token, :validation_failed (the new password
  # itself, from Identity::User's own validation).
  class CompletePasswordReset
    def self.call(...) = new(...).call

    def initialize(token:, password:)
      @token = token
      @password = password
    end

    def call
      user = Identity::User.find_by_password_reset_token(@token)
      return Result.failure(:invalid_token) if user.nil? || user.demo?

      ApplicationRecord.transaction do
        return Result.invalid(user) unless user.update(password: @password)

        Identity::Session.revoke_others_for!(user)
        Rails.logger.info(event: "password_reset_completed", user_id: user.id)
        Result.success(user)
      end
    end
  end
end

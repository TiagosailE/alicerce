module Identity
  # Changes the signed-in user's own password, from their account settings.
  # The policy already denied demo users before this ever runs (ADR 0008:
  # an authentication setting). Revokes every other session of theirs, in
  # every organization (ADR 0007: a stale password is as serious as a
  # stale role), keeping the one making this request alive.
  #
  # Error codes: :invalid_current_password, :validation_failed (the new
  # password itself, from Identity::User's own validation).
  class ChangePassword
    def self.call(...) = new(...).call

    def initialize(user:, current_password:, new_password:, acting_session: nil)
      @user = user
      @current_password = current_password
      @new_password = new_password
      @acting_session = acting_session
    end

    def call
      return Result.failure(:invalid_current_password) unless @user.authenticate(@current_password)

      ApplicationRecord.transaction do
        return Result.invalid(@user) unless @user.update(password: @new_password)

        Identity::Session.revoke_others_for!(@user, except: @acting_session)
        Audit.record("password_changed", @user, actor: @user)
        Result.success(@user)
      end
    end
  end
end

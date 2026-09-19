module Identity
  # Starts a password reset (ADR 0007). Always succeeds and always enqueues
  # the same way, whether or not the email belongs to an account or a demo
  # one (uniform response, the same shape as Identity::User.authenticate_by's
  # failure handling): looking the account up and deciding whether to send
  # happens inside the job instead, after the response has already gone
  # out, so neither the response nor its timing can tell the two apart (a
  # security review found the original version, which enqueued only for a
  # real account, leaked exactly that distinction through response timing).
  class RequestPasswordReset
    def self.call(...) = new(...).call

    def initialize(email:)
      @email = email
    end

    def call
      Identity::PasswordResetMailerJob.perform_later(email: @email)
      Result.success
    end
  end
end

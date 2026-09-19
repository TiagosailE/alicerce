module Identity
  # The first mailer job in the app (PR 6): looks the account up and sends
  # the password reset email through Brevo. Takes the raw email, not the
  # user (Identity::RequestPasswordReset enqueues unconditionally, before
  # knowing whether an account exists, for uniform timing); this job does
  # the lookup, the demo check and the token generation, all after the
  # request has already answered, so none of it can leak through response
  # timing. log_arguments is off: the email is the only argument and must
  # not appear in plain text in the job's own log lines (docs/security.md:
  # personal data filtered from logs).
  class PasswordResetMailerJob < ApplicationJob
    self.log_arguments = false

    retry_on BrevoClient::Error, wait: :polynomially_longer, attempts: 5

    def perform(email:)
      user = Identity::User.find_by(email:)
      return if user.nil? || user.demo?

      token = user.password_reset_token
      link = "https://#{ENV.fetch('APP_HOST')}/redefinir-senha?token=#{token}"

      BrevoClient.deliver(
        to: user.email,
        to_name: user.name,
        subject: "Redefinição de senha - Alicerce",
        html_content: <<~HTML
          <p>Olá, #{ERB::Util.html_escape(user.name)}.</p>
          <p>Use o link abaixo para redefinir sua senha. Ele expira em 20 minutos e só funciona uma vez.</p>
          <p><a href="#{link}">#{ERB::Util.html_escape(link)}</a></p>
        HTML
      )
    end
  end
end

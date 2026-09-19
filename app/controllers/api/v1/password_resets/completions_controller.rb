module Api
  module V1
    module PasswordResets
      # Completes a password reset by its token. Skips authorization for the
      # same reason Invitations::AcceptancesController does: the token is
      # the only credential this action recognizes, before any session
      # exists.
      class CompletionsController < BaseController
        skip_after_action :verify_authorized

        rate_limit to: 10, within: 3.minutes, name: "password_reset_completion_ip"

        before_action :verify_csrf_token!

        def create
          token = params.expect(:token)
          password = params.expect(:password)

          result = Identity::CompletePasswordReset.call(token:, new_password: password)
          return render_result_error(result) unless result.success?

          head :no_content
        end
      end
    end
  end
end

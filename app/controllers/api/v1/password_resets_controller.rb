module Api
  module V1
    # Requests a password reset email. Skips authorization for the same
    # reason SessionsController does (ADR 0008): there is no one signed in
    # yet to check a policy against.
    class PasswordResetsController < BaseController
      skip_after_action :verify_authorized

      rate_limit to: 10, within: 3.minutes, name: "password_reset_request_ip"

      before_action :verify_csrf_token!

      def create
        email = params.expect(:email)

        result = Identity::RequestPasswordReset.call(email:)
        return render_result_error(result) unless result.success?

        head :no_content
      end
    end
  end
end

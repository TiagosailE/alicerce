module Api
  module V1
    module Invitations
      # Accepts a pending invitation by its token. Skips authorization for
      # the same reason SessionsController does (ADR 0008): there is no
      # membership to check before one exists, and the token is the only
      # credential this action recognizes.
      class AcceptancesController < BaseController
        skip_after_action :verify_authorized

        rate_limit to: 10, within: 3.minutes, name: "invitation_acceptance_ip"

        before_action :verify_csrf_token!

        def create
          token = params.expect(:token)
          fields = params.permit(:name, :password)
          invitation = Identity::Invitation.find_by_token(token)

          result = Identity::AcceptInvitation.call(invitation:, name: fields[:name], password: fields[:password])
          return render_result_error(result) unless result.success?

          user = result.value[:user]
          organization = result.value[:membership].organization

          reset_session
          start_browser_session!(user:, organization:)
          Audit.record("signed_in", user, actor: user)

          render json: { data: session_payload(user:, organization:) }, status: :created
        end

        private
          def session_payload(user:, organization:)
            Identity::SessionSerializer.new(csrf_token:, user:, organization:).as_json
          end
      end
    end
  end
end

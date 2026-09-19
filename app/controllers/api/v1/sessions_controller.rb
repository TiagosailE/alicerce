module Api
  module V1
    # Sign-in, sign-out and the current session. Skips authorization (ADR
    # 0008): there is no policy to check before a session exists, and once one
    # exists this controller only ever acts on the caller's own session.
    class SessionsController < BaseController
      rate_limit to: 10, within: 3.minutes, name: "session_create_ip", only: :create
      rate_limit to: 5, within: 3.minutes, name: "session_create_ip_email", only: :create,
        by: -> { "#{request.remote_ip}:#{params[:email].to_s.strip.downcase}" }

      before_action :verify_csrf_token!, only: %i[create destroy]
      before_action :require_authentication!, only: :destroy

      def show
        render json: { data: session_payload(user: Current.user, organization: Current.organization) }
      end

      def create
        email, password = params.expect(:email, :password)
        user = Identity::User.authenticate_by(email:, password:)
        return render_error(status: :unauthorized, code: "unauthenticated", message: "Invalid email or password") unless user

        organization = resolve_organization(user)
        return render_organization_required(user) unless organization

        reset_session
        start_browser_session!(user:, organization:)
        render json: { data: session_payload(user:, organization:) }, status: :created
      end

      def destroy
        end_browser_session!
        reset_session
        render json: { data: session_payload(user: nil, organization: nil) }
      end

      private
        def session_payload(user:, organization:)
          Identity::SessionSerializer.new(csrf_token:, user:, organization:).as_json
        end

        def resolve_organization(user)
          memberships = user.memberships.includes(:organization).to_a
          requested_id = params[:organization_id]

          if requested_id.present?
            memberships.find { |membership| membership.organization_id == requested_id.to_i }&.organization
          elsif memberships.one?
            memberships.first.organization
          end
        end

        def render_organization_required(user)
          memberships = user.memberships.includes(:organization).order(:id)
          render_error(
            status: :unprocessable_content,
            code: "organization_required",
            message: "Choose which organization to sign in to",
            details: { memberships: memberships.map { |membership| Identity::MembershipSerializer.new(membership).as_json } }
          )
        end
    end
  end
end

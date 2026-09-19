module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies

      SESSION_COOKIE = "__Host-session"

      rescue_from ActionController::ParameterMissing, with: :render_parameter_missing
      rescue_from ActionController::TooManyRequests, with: :render_rate_limited
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      before_action :resume_session

      # Routed directly from config/routes.rb for any /api/* path that
      # matched no other route, so unknown API paths get the JSON error
      # envelope instead of the SPA shell or a bare Rails routing error.
      def route_not_found
        render_not_found
      end

      private
        def resume_session
          token = cookies[SESSION_COOKIE]
          return if token.blank?

          record = Identity::Session.resume(token)
          return unless record

          Current.session = record
          Current.user = record.user
          Current.organization = record.organization
        end

        def require_authentication!
          return if Current.user

          render_error(status: :unauthorized, code: "unauthenticated", message: "Sign in required")
        end

        def csrf_token
          session[:csrf_token] ||= SecureRandom.urlsafe_base64(32)
        end

        # Guards every state-changing session action (ADR 0007): the token a
        # prior GET handed out must come back in the header, which is also
        # what stops login CSRF on the sign-in action itself.
        def verify_csrf_token!
          header_token = request.headers["X-CSRF-Token"]
          return if header_token.present? && ActiveSupport::SecurityUtils.secure_compare(header_token, csrf_token)

          render_error(status: :unprocessable_content, code: "invalid_csrf_token", message: "Missing or invalid X-CSRF-Token header")
        end

        # Starts a new browser session for user/organization, deleting
        # whichever session the request cookie carried (ADR 0007: sign-in and
        # organization switch both rotate the session row).
        def start_browser_session!(user:, organization:)
          Current.session&.destroy!

          record, token = Identity::Session.start!(user:, organization:, ip: request.remote_ip, user_agent: request.user_agent)
          write_session_cookie(token)
          Current.session = record
          Current.user = user
          Current.organization = organization
          record
        end

        def end_browser_session!
          Current.session&.destroy!
          clear_session_cookie
          Current.session = nil
          Current.user = nil
          Current.organization = nil
        end

        def write_session_cookie(token)
          cookies[SESSION_COOKIE] = { value: token, secure: true, httponly: true, same_site: :lax, path: "/" }
        end

        def clear_session_cookie
          cookies.delete(SESSION_COOKIE, path: "/")
        end

        def render_error(status:, code:, message:, details: {})
          render status: status, json: { error: { code:, message:, details:, request_id: request.request_id } }
        end

        def render_parameter_missing(exception)
          render_error(
            status: :unprocessable_content,
            code: "validation_failed",
            message: exception.message,
            details: { fields: { exception.param.to_s => [ "blank" ] } }
          )
        end

        def render_rate_limited
          render_error(status: :too_many_requests, code: "rate_limited", message: "Too many requests, try again later")
        end

        def render_not_found
          render_error(status: :not_found, code: "not_found", message: "Not found")
        end
    end
  end
end

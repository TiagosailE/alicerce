module Api
  module V1
    # Changes the signed-in user's own password, from their account
    # settings. No id in the route and no other organization's record is
    # ever reachable (it always acts on Current.user), so it carries no
    # per-role variance either: any role may change their own password
    # except a demo one (ADR 0008), the same shape as the session
    # endpoints, which is why this route is exempt from the isolation and
    # role matrices (spec/requests/api/v1/route_inventory_spec.rb) while
    # still being authorized and directly tested.
    class PasswordsController < BaseController
      # A hijacked or leaked session otherwise gets unlimited attempts to
      # guess the current password (a security review flagged this as the
      # one credential-adjacent action in this app without a rate limit).
      rate_limit to: 5, within: 3.minutes, name: "password_update_ip"

      before_action :require_authentication!
      before_action :verify_csrf_token!

      def update
        authorize(:password, policy_class: Identity::PasswordPolicy)
        current_password, password = params.expect(:current_password, :password)

        result = Identity::ChangePassword.call(
          user: Current.user, current_password:, new_password: password, acting_session: Current.session
        )
        return render_result_error(result) unless result.success?

        head :no_content
      end
    end
  end
end

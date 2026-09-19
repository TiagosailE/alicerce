module Api
  module V1
    module Sessions
      # Switches the signed-in user's active organization. Skips authorization
      # (ADR 0008) for the same reason SessionsController does: membership in
      # the target organization is the only check that applies here.
      class OrganizationsController < BaseController
        before_action :require_authentication!
        before_action :verify_csrf_token!

        def create
          organization_id = params.expect(:organization_id)
          membership = Current.user.memberships.includes(:organization).find_by(organization_id:)
          return render_not_found unless membership

          start_browser_session!(user: Current.user, organization: membership.organization)
          render json: { data: Identity::SessionSerializer.new(csrf_token:, user: Current.user, organization: membership.organization).as_json }
        end
      end
    end
  end
end

module Api
  module V1
    class InvitationsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!

      def create
        authorize(Identity::Invitation)
        email, role = params.expect(:email, :role)

        result = Identity::InviteMember.call(organization: Current.organization, email:, role:, actor: Current.user)
        return render_result_error(result) unless result.success?

        invitation, token = result.value.values_at(:invitation, :token)
        render json: { data: Identity::InvitationSerializer.new(invitation, token:).as_json }, status: :created
      end
    end
  end
end

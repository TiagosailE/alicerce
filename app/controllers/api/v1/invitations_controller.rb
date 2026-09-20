module Api
  module V1
    class InvitationsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create destroy]

      def index
        authorize(Identity::Invitation)
        query = Identity::PendingInvitationsQuery.new(policy_scope(Identity::Invitation), page: params[:page], per_page: params[:per_page])
        render json: { data: query.results.map { |invitation| Identity::PendingInvitationSerializer.new(invitation).as_json }, meta: query.meta }
      end

      def create
        authorize(Identity::Invitation)
        email, role = params.expect(:email, :role)

        result = Identity::InviteMember.call(organization: Current.organization, email:, role:, actor: Current.user)
        return render_result_error(result) unless result.success?

        invitation, token = result.value.values_at(:invitation, :token)
        render json: { data: Identity::InvitationSerializer.new(invitation, token:).as_json }, status: :created
      end

      def destroy
        invitation = Identity::Invitation.find(params[:id])
        authorize(invitation)

        result = Identity::RevokeInvitation.call(invitation:, actor: Current.user)
        return render_result_error(result) unless result.success?

        head :no_content
      end
    end
  end
end

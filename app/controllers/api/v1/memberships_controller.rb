module Api
  module V1
    class MembershipsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!

      def update
        membership = find_membership
        authorize(membership)
        role = params.expect(:role)

        result = Identity::ChangeMemberRole.call(membership:, role:, actor: Current.user, acting_session: Current.session)
        return render_result_error(result) unless result.success?

        render json: { data: Identity::MemberSerializer.new(result.value).as_json }
      end

      def destroy
        membership = find_membership
        authorize(membership)

        result = Identity::RemoveMember.call(membership:, actor: Current.user)
        return render_result_error(result) unless result.success?

        head :no_content
      end

      private
        # identity_memberships carries no RLS (ADR 0003: read across
        # organizations at sign-in by design), so the tenant scope here is
        # this explicit lookup, not the database; another organization's id
        # answers 404 the same way a missing one does.
        def find_membership
          Current.organization.memberships.find(params[:id])
        end
    end
  end
end

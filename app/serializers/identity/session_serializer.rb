module Identity
  # Shapes the response of every /api/v1/session endpoint: the CSRF token the
  # SPA must echo back, who is signed in (if anyone), and which organizations
  # they can switch to.
  class SessionSerializer
    def initialize(csrf_token:, user:, organization:)
      @csrf_token = csrf_token
      @user = user
      @organization = organization
    end

    def as_json
      {
        csrf_token: @csrf_token,
        user: @user && UserSerializer.new(@user).as_json,
        membership: current_membership,
        memberships: @user ? memberships.map { |membership| MembershipSerializer.new(membership).as_json } : []
      }
    end

    private
      def memberships
        @user.memberships.includes(:organization).order(:id)
      end

      def current_membership
        return nil unless @user && @organization

        membership = @user.membership_in(@organization)
        membership && MembershipSerializer.new(membership).as_json
      end
  end
end

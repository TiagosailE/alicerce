module Identity
  # A membership as seen by member-management endpoints: which user, in
  # which role. Distinct from MembershipSerializer, which shapes the
  # signed-in user's own membership inside a session response and has no
  # need to name the user (it is always the caller).
  class MemberSerializer
    def initialize(membership)
      @membership = membership
    end

    def as_json
      { id: @membership.id, user: UserSerializer.new(@membership.user).as_json, role: @membership.role }
    end
  end
end

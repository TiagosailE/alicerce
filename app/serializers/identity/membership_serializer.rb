module Identity
  class MembershipSerializer
    def initialize(membership)
      @membership = membership
    end

    def as_json
      { role: @membership.role, organization: OrganizationSerializer.new(@membership.organization).as_json }
    end
  end
end

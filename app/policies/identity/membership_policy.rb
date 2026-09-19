module Identity
  class MembershipPolicy < ApplicationPolicy
    def update?
      manage_members?
    end

    def destroy?
      manage_members?
    end

    private
      def manage_members?
        Identity::Capabilities.manage_members?(user, user&.membership_in(Current.organization))
      end
  end
end

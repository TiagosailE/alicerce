module Identity
  class InvitationPolicy < ApplicationPolicy
    def create?
      Identity::Capabilities.manage_members?(user, membership)
    end

    def index?
      Identity::Capabilities.manage_members?(user, membership)
    end

    def destroy?
      Identity::Capabilities.manage_members?(user, membership)
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.manage_members?(user, membership) ? scope.pending : scope.none
      end

      private
        def membership
          user&.membership_in(Current.organization)
        end
    end

    private
      def membership
        user&.membership_in(Current.organization)
      end
  end
end

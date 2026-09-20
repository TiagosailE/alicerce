module Identity
  class MembershipPolicy < ApplicationPolicy
    def index?
      manage_members?
    end

    def update?
      manage_members?
    end

    def destroy?
      manage_members?
    end

    # identity_memberships carries no RLS (ADR 0003: read across
    # organizations at sign-in by design, see MembershipsController), so
    # the tenant scope for the index is this explicit association, not the
    # scope class Pundit hands in.
    class Scope < ApplicationPolicy::Scope
      def resolve
        manage_members? ? Current.organization.memberships : Identity::Membership.none
      end

      private
        def manage_members?
          Identity::Capabilities.manage_members?(user, user&.membership_in(Current.organization))
        end
    end

    private
      def manage_members?
        Identity::Capabilities.manage_members?(user, user&.membership_in(Current.organization))
      end
  end
end

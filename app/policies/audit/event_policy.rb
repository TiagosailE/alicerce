module Audit
  class EventPolicy < ApplicationPolicy
    def index?
      Identity::Capabilities.view_audit_trail?(membership)
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.view_audit_trail?(membership) ? scope.all : scope.none
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

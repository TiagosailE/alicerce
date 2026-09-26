module Inventory
  class MovementPolicy < ApplicationPolicy
    def index? = Identity::Capabilities.view_stock_movements?(user&.membership_in(Current.organization))

    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.view_stock_movements?(user&.membership_in(Current.organization)) ? scope.all : scope.none
      end
    end
  end
end

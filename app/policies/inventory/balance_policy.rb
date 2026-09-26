module Inventory
  class BalancePolicy < ApplicationPolicy
    def index? = view_stock?

    # Whether the response carries what stock is worth and cost (margin data).
    def view_value? = Identity::Capabilities.view_stock_value?(membership)

    # Whether the caller may record a stock adjustment. Not a Rails action of
    # the balances resource: the adjustments endpoint authorizes through it.
    def adjust? = Identity::Capabilities.adjust_stock?(membership)

    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.view_stock?(user&.membership_in(Current.organization)) ? scope.all : scope.none
      end
    end

    private
      def membership = user&.membership_in(Current.organization)

      def view_stock? = Identity::Capabilities.view_stock?(membership)
  end
end

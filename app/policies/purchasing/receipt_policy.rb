module Purchasing
  class ReceiptPolicy < ApplicationPolicy
    def index? = view_purchasing?
    def show? = view_purchasing?
    def create? = manage_purchasing?

    # The payable a receipt opened is what the organization owes: shown on the
    # receipt only to a role that reads payables.
    def view_payable? = Identity::Capabilities.view_payables?(membership)

    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.view_purchasing?(user&.membership_in(Current.organization)) ? scope.all : scope.none
      end
    end

    private
      def membership = user&.membership_in(Current.organization)

      def view_purchasing? = Identity::Capabilities.view_purchasing?(membership)

      def manage_purchasing? = Identity::Capabilities.manage_purchasing?(membership)
  end
end

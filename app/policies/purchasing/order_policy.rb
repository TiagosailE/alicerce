module Purchasing
  class OrderPolicy < ApplicationPolicy
    def index? = view_purchasing?
    def show? = view_purchasing?
    def create? = manage_purchasing?
    def update? = manage_purchasing?
    def approve? = manage_purchasing?
    def cancel? = manage_purchasing?

    # The supplier's CPF is masked for a role that may not see a partner's in
    # full (ADR 0014), here as on the partner itself.
    def view_personal_data?
      Identity::Capabilities.view_partner_personal_data?(membership)
    end

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

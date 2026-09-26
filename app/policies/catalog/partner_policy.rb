module Catalog
  class PartnerPolicy < ApplicationPolicy
    def index? = view_master_data?
    def show? = view_master_data?
    def create? = manage_master_data?
    def update? = manage_master_data?

    # Not an action: whether the response for this partner carries the
    # personal fields in full (ADR 0014).
    def view_personal_data?
      Identity::Capabilities.view_partner_personal_data?(user&.membership_in(Current.organization))
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        view_master_data? ? scope.all : scope.none
      end

      private
        def view_master_data?
          Identity::Capabilities.view_master_data?(user&.membership_in(Current.organization))
        end
    end

    private
      def manage_master_data?
        Identity::Capabilities.manage_master_data?(user&.membership_in(Current.organization))
      end

      def view_master_data?
        Identity::Capabilities.view_master_data?(user&.membership_in(Current.organization))
      end
  end
end

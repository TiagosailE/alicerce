module Finance
  class TitlePolicy < ApplicationPolicy
    def index? = Identity::Capabilities.view_payables?(user&.membership_in(Current.organization))

    # What this policy lets a reader see are payables: receivables get a policy
    # and capability of their own when invoices arrive, so a reader of one never
    # reads the other by accident.
    class Scope < ApplicationPolicy::Scope
      def resolve
        Identity::Capabilities.view_payables?(user&.membership_in(Current.organization)) ? scope.where(kind: "payable") : scope.none
      end
    end
  end
end

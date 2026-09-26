# Every write that costs permanent rows (an order, an approval, a receipt, a
# stock count) counts against one budget per user and one for the organization
# as a whole: a 200-line order costs hundreds of queries and a receipt writes
# rows the app role can never delete, while the demo accounts are shared and
# public. The counters are shared by every controller that includes this, so
# alternating between endpoints cannot multiply the allowance.
#
# The organization's counter only counts requests from someone allowed to write
# in the area (counts_toward_organization_limit?), so a user who is not, a demo
# salesperson looping on a forbidden endpoint, can only spend their own budget
# and never the allowance the people who do the work rely on. These callbacks
# run after the base controller's session callback, so Current.user is set.
module LedgerWriteLimits
  extend ActiveSupport::Concern

  included do
    rate_limit to: 60, within: 1.minute, name: "user", scope: "ledger_writes",
      by: -> { Current.user&.id || request.remote_ip }, if: -> { !request.get? }
    rate_limit to: 200, within: 10.minutes, name: "organization", scope: "ledger_writes",
      by: -> { Current.organization&.id || request.remote_ip }, if: -> { !request.get? && counts_toward_organization_limit? }
  end

  private
    def counts_toward_organization_limit?
      Identity::Capabilities.manage_purchasing?(Current.user&.membership_in(Current.organization))
    end
end

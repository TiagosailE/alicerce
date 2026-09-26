# Every write that costs permanent rows (an order, an approval, a receipt, a
# stock count) counts against one budget per user and one for the organization
# as a whole: a 200-line order costs hundreds of queries and a receipt writes
# rows the app role can never delete, while the demo accounts are shared and
# public. The counters are shared by every controller that includes this, so
# alternating between endpoints cannot multiply the allowance.
#
# The two budgets count different things. The user's counts every attempt,
# whatever came of it, because that is what bounds the cost of one client looping
# on a request. The organization's counts only writes that succeeded, because
# what it protects is the permanent rows the organization owns: a request that
# was refused leaves none, and letting failures spend it would let one looping
# client, or one form retried on a validation error, lock every colleague out for
# ten minutes.
#
# The organization's budget only counts requests from someone allowed to write
# in the area (counts_toward_organization_limit?), so a user who is not, a demo
# salesperson looping on a forbidden endpoint, can only spend their own budget
# and never the allowance the people who do the work rely on. These callbacks
# run after the base controller's session callback, so Current.user is set. The
# organization's count is read before the write and raised after it, so requests
# in flight together can pass the ceiling by as many as were in flight.
module LedgerWriteLimits
  extend ActiveSupport::Concern

  USER_WRITES_PER_MINUTE = 60
  ORGANIZATION_WRITES_PER_TEN_MINUTES = 200

  # The counter's key, for the callbacks below and for a spec that needs to
  # bring it to the ceiling without making that many writes.
  def self.budget_key(scope:, name:, organization_id:)
    [ "rate-limit", scope, name, organization_id ].join(":")
  end

  included do
    rate_limit to: USER_WRITES_PER_MINUTE, within: 1.minute, name: "user", scope: "ledger_writes",
      by: -> { Current.user&.id || request.remote_ip }, if: -> { !request.get? }
    organization_budget to: ORGANIZATION_WRITES_PER_TEN_MINUTES, within: 10.minutes, name: "organization", scope: "ledger_writes"
  end

  class_methods do
    # A ceiling on the writes that succeeded for one organization: refused with a
    # 429 once it is reached, spent only by a 2xx answer.
    def organization_budget(to:, within:, name:, scope:)
      before_action(if: -> { !request.get? && counts_toward_organization_limit? }) do
        raise ActionController::TooManyRequests if organization_writes(scope:, name:) >= to
      end
      after_action(if: -> { !request.get? && counts_toward_organization_limit? && response.successful? }) do
        cache_store.increment(organization_budget_key(scope:, name:), 1, expires_in: within)
      end
    end
  end

  private
    def counts_toward_organization_limit?
      Identity::Capabilities.manage_purchasing?(Current.user&.membership_in(Current.organization))
    end

    def organization_budget_key(scope:, name:)
      LedgerWriteLimits.budget_key(scope:, name:, organization_id: Current.organization.id)
    end

    def organization_writes(scope:, name:)
      cache_store.read(organization_budget_key(scope:, name:)).to_i
    end
end

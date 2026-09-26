# Each purchasing write costs queries, a permanent row and an audit event, and a
# 200-line order costs hundreds of queries, while the demo accounts are shared
# and public: a ceiling per user and one for the organization as a whole keeps a
# loop from saturating the few database connections (the same shape as stock
# adjustments).
module PurchasingWriteLimits
  extend ActiveSupport::Concern

  included do
    rate_limit to: 60, within: 1.minute, name: "purchasing_write_user",
      by: -> { Current.user&.id || request.remote_ip }, if: -> { !request.get? }
    rate_limit to: 200, within: 10.minutes, name: "purchasing_write_organization",
      by: -> { Current.organization&.id || request.remote_ip }, if: -> { !request.get? }
  end
end

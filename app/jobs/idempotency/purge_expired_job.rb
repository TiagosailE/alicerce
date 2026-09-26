# ADR 0005: idempotency keys live for 24 hours. The table is under row level
# security, so the sweep runs organization by organization with the tenant set,
# the same way a request does, and always clears it again.
module Idempotency
  class PurgeExpiredJob < ApplicationJob
    RETENTION = 24.hours

    def perform
      Identity::Organization.find_each do |organization|
        purge(organization)
      end
    end

    private
      def purge(organization)
        Current.organization = organization
        TenantSetting.apply!(organization.id)
        IdempotencyKey.where(created_at: ...RETENTION.ago).delete_all
      ensure
        TenantSetting.clear!
        Current.organization = nil
      end
  end
end

# Current.organization alone is not enough outside a real request: RLS
# checks the Postgres session setting, not the Ruby object, so specs that
# create or query tenant-scoped rows directly need both in sync.
module TenantContext
  def set_current_tenant(organization)
    Current.organization = organization
    TenantSetting.apply!(organization.id)
  end
end

RSpec.configure do |config|
  config.include TenantContext
  config.after(:each) { TenantSetting.clear! }
  config.after(:each) { Current.reset }
end

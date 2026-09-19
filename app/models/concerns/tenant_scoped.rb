# Every tenant model includes this (ADR 0003): scoped to Current.organization,
# raising instead of silently returning every organization's rows when it is
# nil, which is a programmer error (the controller always sets it before a
# tenant model is queried), not a legitimate empty result.
module TenantScoped
  extend ActiveSupport::Concern

  class NoTenantError < StandardError; end

  included do
    belongs_to :organization, class_name: "Identity::Organization"

    default_scope do
      raise NoTenantError, "#{name} was queried with no current organization" unless Current.organization

      where(organization: Current.organization)
    end
  end
end

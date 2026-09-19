# Applies and clears the app.organization_id Postgres session setting RLS
# policies read (ADR 0003), on the connection the request leased. Two lines
# of defense: the caller resets it in an ensure block when the request ends,
# and .install! patches the pool so a connection that still carries a tenant
# is cleaned the moment it is checked in, in case the ensure never ran.
module TenantSetting
  SETTING = "app.organization_id".freeze

  module_function

  def apply!(organization_id, connection: ActiveRecord::Base.lease_connection)
    connection.execute("SELECT set_config(#{connection.quote(SETTING)}, #{connection.quote(organization_id.to_s)}, false)")
    connection.instance_variable_set(:@tenant_setting_applied, true)
  end

  def clear!(connection: ActiveRecord::Base.lease_connection)
    reset(connection)
  end

  def reset(connection)
    return unless connection.instance_variable_get(:@tenant_setting_applied)

    connection.execute("SELECT set_config(#{connection.quote(SETTING)}, '', false)")
    connection.instance_variable_set(:@tenant_setting_applied, false)
  end

  def install!
    ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(PoolCheckin)
  end

  module PoolCheckin
    def checkin(conn)
      TenantSetting.reset(conn)
      super
    end
  end
end

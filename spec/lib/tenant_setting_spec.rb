require "rails_helper"

RSpec.describe TenantSetting do
  # Uses a real checkout/checkin, not the connection RSpec pins for
  # transactional fixtures (checkin on a pinned connection is a no-op), so
  # the pool patch under test actually runs.
  self.use_transactional_tests = false

  let(:pool) { ActiveRecord::Base.connection_pool }
  let(:organization_id) { 4242 }

  def current_setting(connection)
    connection.select_value("SELECT current_setting('app.organization_id', true)")
  end

  after { pool.connections.each { |conn| described_class.reset(conn) } }

  it "sets app.organization_id on the leased connection" do
    connection = pool.checkout

    described_class.apply!(organization_id, connection:)

    expect(current_setting(connection)).to eq(organization_id.to_s)
  ensure
    pool.checkin(connection)
  end

  it "clears it back to blank, not to null" do
    connection = pool.checkout
    described_class.apply!(organization_id, connection:)

    described_class.clear!(connection:)

    expect(current_setting(connection)).to eq("")
  ensure
    pool.checkin(connection)
  end

  it "resets a connection that still carries a tenant the moment it is checked in" do
    connection = pool.checkout
    described_class.apply!(organization_id, connection:)

    pool.checkin(connection)

    expect(current_setting(connection)).to eq("")
  end

  it "does not touch a connection that never carried a tenant" do
    connection = pool.checkout
    connection.execute("SELECT set_config('app.organization_id', '#{organization_id}', false)")

    pool.checkin(connection)

    expect(current_setting(connection)).to eq(organization_id.to_s)
  ensure
    connection.execute("SELECT set_config('app.organization_id', '', false)")
  end
end

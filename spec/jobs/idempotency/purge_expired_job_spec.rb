require "rails_helper"

RSpec.describe Idempotency::PurgeExpiredJob do
  let(:user) { create(:user) }
  let(:first_organization) { create(:organization) }
  let(:second_organization) { create(:organization) }

  def key_for(organization, created_at:, key: "key-#{SecureRandom.hex(6)}")
    set_current_tenant(organization)
    IdempotencyKey.create!(organization:, user:, key:, request_digest: "digest", created_at:)
  end

  def keys_of(organization)
    set_current_tenant(organization)
    IdempotencyKey.pluck(:key)
  end

  it "deletes keys older than a day in every organization and keeps the newer ones" do
    key_for(first_organization, created_at: 25.hours.ago, key: "old-first-org")
    key_for(first_organization, created_at: 23.hours.ago, key: "fresh-first-org")
    key_for(second_organization, created_at: 3.days.ago, key: "old-second-org")
    key_for(second_organization, created_at: 1.hour.ago, key: "fresh-second-org")

    described_class.perform_now

    expect(keys_of(first_organization)).to eq([ "fresh-first-org" ])
    expect(keys_of(second_organization)).to eq([ "fresh-second-org" ])
  end

  it "leaves no tenant set on the connection afterwards" do
    key_for(first_organization, created_at: 2.days.ago)

    described_class.perform_now

    expect(ActiveRecord::Base.connection.select_value("SELECT current_setting('app.organization_id', true)").to_s).to eq("")
    expect(Current.organization).to be_nil
  end

  it "does nothing when there is nothing to delete" do
    expect { described_class.perform_now }.not_to raise_error
  end
end

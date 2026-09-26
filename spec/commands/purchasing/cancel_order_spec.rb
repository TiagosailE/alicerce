require "rails_helper"

RSpec.describe Purchasing::CancelOrder do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  def order_in(status) = create(:purchase_order, organization:, status:)

  %w[draft approved partially_received].each do |status|
    it "cancels a #{status} order, stamping who and when, and records it" do
      order = order_in(status)

      result = described_class.call(order:, actor:)

      expect(result).to be_success
      expect(order.reload).to have_attributes(status: "cancelled", cancelled_by_user_id: actor.id, revision: 1)
      expect(order.cancelled_at).to be_within(5.seconds).of(Time.current)
      expect(Audit::Event.where(action: "purchase_order_cancelled").sole.field_changes).to include("status" => { "from" => status, "to" => "cancelled" })
    end
  end

  %w[received cancelled].each do |status|
    it "refuses a #{status} order with invalid_transition" do
      order = order_in(status)

      expect(described_class.call(order:, actor:).error).to eq(:invalid_transition)
      expect(order.reload.status).to eq(status)
    end
  end
end

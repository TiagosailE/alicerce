require "rails_helper"

RSpec.describe Purchasing::Order do
  let(:organization) { create(:organization) }

  before { set_current_tenant(organization) }

  it_behaves_like "a state machine" do
    def record_in(status) = create(:purchase_order, organization:, status:)
  end

  it "has the transition table of ADR 0017" do
    expect(described_class::TRANSITIONS).to eq(
      "draft" => %w[approved cancelled],
      "approved" => %w[partially_received received cancelled],
      "partially_received" => %w[partially_received received cancelled],
      "received" => [],
      "cancelled" => []
    )
  end

  it "stores the supplier's document number encrypted, and reads it back" do
    supplier = supplier_for(organization)
    order = create(:purchase_order, organization:, supplier:)

    raw = ActiveRecord::Base.connection.select_value("SELECT supplier_document_number FROM purchasing_orders WHERE id = #{order.id}")

    expect(raw).not_to include(supplier.document_number)
    expect(order.reload.supplier_document_number).to eq(supplier.document_number)
  end

  it "keeps installments within 1 to 24 and the day terms within a year" do
    order = build(:purchase_order, organization:, installments: 25, first_due_days: -1, interval_days: 366)

    expect(order).not_to be_valid
    expect(order.errors.attribute_names).to include(:installments, :first_due_days, :interval_days)
  end
end

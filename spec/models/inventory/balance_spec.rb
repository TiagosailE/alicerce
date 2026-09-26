require "rails_helper"

RSpec.describe Inventory::Balance do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  before { set_current_tenant(organization) }

  describe ".lock_for" do
    let(:loja) { create(:warehouse, organization:, name: "Loja") }
    let(:patio) { create(:warehouse, organization:, name: "Patio") }
    let(:cimento) { create(:product, organization:) }
    let(:areia) { create(:product, organization:) }

    it "creates the missing balances at zero and returns them in ascending order" do
      pairs = [ [ areia.id, patio.id ], [ cimento.id, loja.id ], [ cimento.id, patio.id ] ]

      balances = described_class.lock_for(organization:, pairs:)

      expect(balances.map { |balance| [ balance.product_id, balance.warehouse_id ] }).to eq(pairs.sort)
      expect(balances).to all(have_attributes(on_hand: 0, reserved: 0, negative_allowance: 0, value_cents: 0, currency: "BRL"))
      expect(described_class.count).to eq(3)
    end

    # The lock order of ADR 0004 is what keeps two commands that need the same
    # balances from deadlocking. A threaded spec cannot prove it (Postgres
    # locks rows in scan order and the INSERT window is microseconds; removing
    # the ordering left such a spec green), so this reads the SQL contract:
    # the missing rows are inserted in ascending order and the rows are locked
    # by a SELECT ordered the same way.
    it "inserts and locks in ascending (product_id, warehouse_id) order whatever order it is asked in" do
      low, high = [ cimento, areia ].sort_by(&:id)
      pairs = [ [ high.id, patio.id ], [ low.id, loja.id ], [ low.id, patio.id ] ]
      statements = []
      collector = ->(*, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(collector, "sql.active_record") do
        described_class.lock_for(organization:, pairs:)
      end

      insert = statements.find { |sql| sql.start_with?("INSERT INTO \"inventory_balances\"") }
      positions = pairs.sort.map { |product_id, warehouse_id| insert.index("(#{organization.id}, #{product_id}, #{warehouse_id}") }
      expect(positions).to all(be_present)
      expect(positions).to eq(positions.sort)

      locking = statements.find { |sql| sql.include?("FOR NO KEY UPDATE") }
      expect(locking).to include('ORDER BY "inventory_balances"."product_id" ASC, "inventory_balances"."warehouse_id" ASC')
    end

    it "leaves an existing balance untouched and never duplicates it" do
      described_class.lock_for(organization:, pairs: [ [ cimento.id, loja.id ] ]).sole.update!(on_hand: 7, value_cents: 70)

      again = described_class.lock_for(organization:, pairs: [ [ cimento.id, loja.id ], [ cimento.id, loja.id ] ])

      expect(again.size).to eq(1)
      expect(again.sole).to have_attributes(on_hand: BigDecimal("7"), value_cents: 70)
      expect(described_class.count).to eq(1)
    end

    it "does not reach another organization's balance for the same ids" do
      set_current_tenant(other_organization)
      foreign = create(:product, organization: other_organization)
      foreign_warehouse = create(:warehouse, organization: other_organization)
      described_class.lock_for(organization: other_organization, pairs: [ [ foreign.id, foreign_warehouse.id ] ])

      set_current_tenant(organization)
      expect(described_class.count).to eq(0)
      # A savepoint, so the rejected INSERT does not abort the spec's own transaction.
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          described_class.lock_for(organization:, pairs: [ [ foreign.id, foreign_warehouse.id ] ])
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "#available" do
    it "is on_hand minus reserved" do
      expect(described_class.new(on_hand: BigDecimal("10"), reserved: BigDecimal("3.5")).available).to eq(BigDecimal("6.5"))
    end
  end
end

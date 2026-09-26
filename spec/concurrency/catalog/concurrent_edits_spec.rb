require "rails_helper"

RSpec.describe "concurrent edits of the same product or partner (ADR 0015)" do
  # Real threads and committed rows: the lost update only exists across
  # separate Postgres transactions actually overlapping in time.
  self.use_transactional_tests = false

  ROUNDS = 12

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # The organization, the actor and the audit events are permanent leftovers
  # (audit_events is append-only, ADR 0010); only the rows under test go.
  after do
    set_current_tenant(@organization)
    [ Catalog::UnitConversion, Catalog::Product, Catalog::Unit, Catalog::Partner ].each(&:delete_all)
  end

  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
  end

  it "lets exactly one of two product edits based on the same revision win, and never reverts the other" do
    unit = create(:unit, organization: @organization)

    ROUNDS.times do |round|
      product = create(:product, organization: @organization, sku: "P-#{round}", stock_unit: unit)
      create(:unit_conversion, organization: @organization, product:, purchase_unit: unit, factor: "1")
      edit = lambda do |name, factor|
        lambda do
          set_current_tenant(@organization)
          Catalog::UpdateProduct.call(
            product: Catalog::Product.find(product.id), revision: 0, actor: @actor,
            attributes: { sku: product.sku, name:, stock_unit_id: unit.id, active: true },
            conversion_attributes: { purchase_unit_id: unit.id, factor: }
          )
        end
      end

      results = run_concurrently(edit.call("Nome A", "10"), edit.call("Nome B", "20"))

      expect(results.map(&:success?)).to contain_exactly(true, false)
      expect(results.reject(&:success?).sole.error).to eq(:stale)
      product.reload
      expect(product.revision).to eq(1)
      # The winner's name and factor both stand: the loser wrote nothing.
      winner_is_a = product.name == "Nome A"
      expect(product.unit_conversion.factor).to eq(BigDecimal(winner_is_a ? "10" : "20"))
    end
  end

  it "does the same for two partner edits" do
    ROUNDS.times do |round|
      partner = create(:partner, organization: @organization, name: "Original #{round}")
      edit = lambda do |name|
        lambda do
          set_current_tenant(@organization)
          Catalog::UpdatePartner.call(
            partner: Catalog::Partner.find(partner.id), revision: 0, actor: @actor,
            attributes: { name:, document_type: partner.document_type, document_number: partner.document_number,
              customer: true, supplier: false, active: true }
          )
        end
      end

      results = run_concurrently(edit.call("Nome A"), edit.call("Nome B"))

      expect(results.map(&:success?)).to contain_exactly(true, false)
      expect(results.reject(&:success?).sole.error).to eq(:stale)
      expect(partner.reload.revision).to eq(1)
    end
  end
end

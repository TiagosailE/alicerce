require "rails_helper"
require "concurrent/atomic/cyclic_barrier"

RSpec.describe "concurrent writes of the same unique value in master data" do
  # Real threads and committed rows, not the connection RSpec pins for
  # transactional fixtures: the race only exists across separate Postgres
  # transactions actually overlapping in time.
  self.use_transactional_tests = false

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  # Holds every save of the model at a rendezvous placed after validation
  # and before the INSERT, so both requests are guaranteed to have passed
  # the uniqueness validation's SELECT before either one writes. Without
  # this the test would only hit the race when the scheduler happened to
  # line the threads up, and pass silently the rest of the time.
  def hold_saves_until_both_validated(model)
    rendezvous = Concurrent::CyclicBarrier.new(2)
    hook = ->(_record) { raise "the two saves never met" unless rendezvous.wait(5) }
    model.set_callback(:save, :before, hook)
    @held_models << [ model, hook ]
  end

  # Builds and saves one record per thread, both held at the rendezvous.
  # Returns [saved?, record] pairs; a RecordInvalid from save! counts as
  # "not saved", while any other exception (RecordNotUnique above all)
  # propagates through Thread#value and fails the example.
  def race(model, builders, writer: :save)
    hold_saves_until_both_validated(model)
    jobs = builders.map do |build|
      lambda do
        set_current_tenant(@organization)
        record = build.call
        saved = begin
          record.public_send(writer)
        rescue ActiveRecord::RecordInvalid
          false
        end
        [ saved, record ]
      end
    end
    run_concurrently(*jobs)
  end

  def expect_one_winner_and_a_taken_error(results, attribute)
    expect(results.map(&:first)).to contain_exactly(true, false)
    loser = results.find { |saved, _record| !saved }.last
    expect(loser.errors.details[attribute].pluck(:error)).to include(:taken)
  end

  # The organization, the actor users and the audit events these tests
  # commit are not cleaned up: audit_events is append-only for every role
  # but the owner (ADR 0010) and references both by a real foreign key. Only
  # the rows under test are removed; the actor gets a random email so a
  # later run's factory sequence never collides with a permanent leftover.
  before { @held_models = [] }

  after do
    @held_models.each { |model, hook| model.skip_callback(:save, :before, hook) }
    set_current_tenant(@organization)
    [ Catalog::UnitConversion, Catalog::Product, Catalog::Category, Catalog::Unit,
      Catalog::Partner, Inventory::Warehouse ].each(&:delete_all)
  end

  def setup_tenant
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
  end

  describe "through the commands" do
    it "answers validation_failed to the loser when two units are created with the same code" do
      setup_tenant
      hold_saves_until_both_validated(Catalog::Unit)

      results = run_concurrently(
        -> {
          set_current_tenant(@organization)
          Catalog::CreateUnit.call(organization: @organization, code: "SC", name: "Saco", actor: @actor)
        },
        -> {
          set_current_tenant(@organization)
          Catalog::CreateUnit.call(organization: @organization, code: "SC", name: "Outro saco", actor: @actor)
        }
      )

      expect(results.map(&:success?)).to contain_exactly(true, false)
      loser = results.reject(&:success?).sole
      expect(loser.error).to eq(:validation_failed)
      expect(loser.details[:fields]["code"]).to include("taken")
      set_current_tenant(@organization)
      expect(Catalog::Unit.count).to eq(1)
    end

    it "answers validation_failed when a rename races a create for the same name" do
      setup_tenant
      existing = create(:category, organization: @organization, name: "Hidraulica")
      hold_saves_until_both_validated(Catalog::Category)

      results = run_concurrently(
        -> {
          set_current_tenant(@organization)
          Catalog::CreateCategory.call(organization: @organization, name: "Eletrica", actor: @actor)
        },
        -> {
          set_current_tenant(@organization)
          Catalog::UpdateCategory.call(category: Catalog::Category.find(existing.id), attributes: { name: "eletrica" }, actor: @actor)
        }
      )

      expect(results.map(&:success?)).to contain_exactly(true, false)
      expect(results.reject(&:success?).sole.details[:fields]["name"]).to include("taken")
      # Either side may win: a created "Eletrica" leaves two categories, a
      # renamed one leaves a single "eletrica". What must hold is that the
      # index never ends up with the same name twice.
      set_current_tenant(@organization)
      names = Catalog::Category.pluck(:name).map(&:downcase)
      expect(names).to eq(names.uniq)
    end
  end

  describe "at the model, for every model that includes RaceSafeUniqueness" do
    it "reports a duplicate category name that differs only by case" do
      setup_tenant
      results = race(Catalog::Category, [
        -> { Catalog::Category.new(organization: @organization, name: "Ferragens") },
        -> { Catalog::Category.new(organization: @organization, name: "FERRAGENS") }
      ])

      expect_one_winner_and_a_taken_error(results, :name)
    end

    it "reports a duplicate product sku" do
      setup_tenant
      unit = create(:unit, organization: @organization)
      results = race(Catalog::Product, [
        -> { Catalog::Product.new(organization: @organization, sku: "TIJ-001", name: "Tijolo", stock_unit_id: unit.id) },
        -> { Catalog::Product.new(organization: @organization, sku: "tij-001", name: "Outro tijolo", stock_unit_id: unit.id) }
      ])

      expect_one_winner_and_a_taken_error(results, :sku)
    end

    it "reports a duplicate warehouse name" do
      setup_tenant
      results = race(Inventory::Warehouse, [
        -> { Inventory::Warehouse.new(organization: @organization, name: "Loja") },
        -> { Inventory::Warehouse.new(organization: @organization, name: "LOJA") }
      ])

      expect_one_winner_and_a_taken_error(results, :name)
    end

    it "reports a duplicate partner document, which the index compares as ciphertext" do
      setup_tenant
      build = lambda do |name|
        -> {
          Catalog::Partner.new(organization: @organization, name:, document_type: "cpf",
            document_number: "52998224725", customer: true)
        }
      end
      results = race(Catalog::Partner, [ build.call("Cliente A"), build.call("Cliente B") ])

      expect_one_winner_and_a_taken_error(results, :document_number)
    end

    it "reports a second unit conversion for the same product" do
      setup_tenant
      product = create(:product, organization: @organization)
      unit_id = product.stock_unit_id
      build = -> { Catalog::UnitConversion.new(organization: @organization, product_id: product.id, purchase_unit_id: unit_id, factor: 2) }
      results = race(Catalog::UnitConversion, [ build, build ])

      expect_one_winner_and_a_taken_error(results, :product_id)
    end

    it "makes create! raise RecordInvalid, never RecordNotUnique" do
      setup_tenant
      results = race(Inventory::Warehouse, [
        -> { Inventory::Warehouse.new(organization: @organization, name: "Patio") },
        -> { Inventory::Warehouse.new(organization: @organization, name: "patio") }
      ], writer: :save!)

      expect_one_winner_and_a_taken_error(results, :name)
    end
  end
end

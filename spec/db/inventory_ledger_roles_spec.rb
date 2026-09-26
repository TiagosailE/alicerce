require "rails_helper"

# What the ledger's second layer and its erasure function do for the roles that
# can reach them, which the app role cannot show: the app has no UPDATE, DELETE
# or TRUNCATE, so its own examples only ever meet the revoke, and inverting a
# trigger would leave them green. Committed rows and separate connections, so
# nothing here runs inside the examples' transaction. The leftovers are
# unavoidable (the ledger is append-only) and harmless: each example builds its
# own organization and gives its user a random email.
RSpec.describe "Inventory ledger, as the roles that hold its privileges" do
  include OwnerConnection

  self.use_transactional_tests = false

  PROBE_ROLE = "ledger_probe".freeze

  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    @movement = Inventory::Movement.create!(
      organization: @organization, product: create(:product, organization: @organization),
      warehouse: create(:warehouse, organization: @organization), kind: "adjustment", reason: "count", quantity: 1,
      value_cents: 1, on_hand_after: 1, value_after_cents: 1, actor_user: @actor, note: "Cliente Joao Silva"
    )
  end

  def note_now
    set_current_tenant(@organization)
    ActiveRecord::Base.connection.select_value("SELECT note FROM inventory_movements WHERE id = #{@movement.id}")
  end

  describe "inventory_movement_redact_note" do
    it "is refused to the application role" do
      expect do
        ActiveRecord::Base.transaction(requires_new: true) do
          ActiveRecord::Base.connection.execute("SELECT inventory_movement_redact_note(#{@organization.id}, #{@movement.id})")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /permission denied for function/)
      expect(note_now).to eq("Cliente Joao Silva")
    end

    it "blanks the note when the owner calls it for the organization it is working in, and only then" do
      with_owner_connection do |owner|
        owner.exec("SELECT set_config('app.organization_id', '#{@organization.id}', false)")

        expect(owner.exec("SELECT inventory_movement_redact_note(#{@organization.id + 1}, #{@movement.id})").first)
          .to be_nil
      rescue PG::RaiseException => error
        expect(error.message).to match(/not the current organization/)
        expect(note_now).to eq("Cliente Joao Silva")

        result = owner.exec("SELECT inventory_movement_redact_note(#{@organization.id}, #{@movement.id})")
        expect(result.getvalue(0, 0).to_i).to eq(1)
      end

      expect(note_now).to be_nil
    end
  end

  describe "the append-only triggers" do
    around do |example|
      with_owner_connection do |owner|
        owner.exec(<<~SQL)
          DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{PROBE_ROLE}') THEN CREATE ROLE #{PROBE_ROLE} NOLOGIN; END IF;
          END $$;
          GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON inventory_movements TO #{PROBE_ROLE};
          GRANT #{PROBE_ROLE} TO CURRENT_USER;
        SQL
        @owner = owner
        example.run
      ensure
        owner.exec("DROP OWNED BY #{PROBE_ROLE}; DROP ROLE IF EXISTS #{PROBE_ROLE}")
      end
    end

    # A role that DOES hold UPDATE, DELETE and TRUNCATE gets past the privilege
    # layer, so only the triggers stand between it and the ledger.
    def as_probe(statement)
      @owner.exec("BEGIN")
      @owner.exec("SET LOCAL ROLE #{PROBE_ROLE}")
      @owner.exec("SELECT set_config('app.organization_id', '#{@organization.id}', true)")
      @owner.exec(statement)
    ensure
      @owner.exec("ROLLBACK")
    end

    it "refuses an UPDATE, a DELETE and a TRUNCATE from a role that has the privileges but does not own the table" do
      expect { as_probe("UPDATE inventory_movements SET quantity = 99 WHERE id = #{@movement.id}") }
        .to raise_error(PG::RaiseException, /append-only: UPDATE is not permitted/)
      expect { as_probe("DELETE FROM inventory_movements WHERE id = #{@movement.id}") }
        .to raise_error(PG::RaiseException, /append-only: DELETE is not permitted/)
      expect { as_probe("TRUNCATE inventory_movements") }
        .to raise_error(PG::RaiseException, /append-only: TRUNCATE is not permitted/)
    end
  end
end

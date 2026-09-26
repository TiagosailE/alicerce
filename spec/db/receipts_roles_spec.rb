require "rails_helper"

# The receipts' second layer, for a role that holds the privileges the app role
# does not: only the triggers stand between it and a posted receipt. Committed
# rows and separate connections; the leftovers are unavoidable (the receipt is
# append-only) and harmless, as for the ledger: every example builds its own
# organization and gives its user a random email.
RSpec.describe "Receipts, as a role that holds the privileges but does not own the tables" do
  include OwnerConnection

  self.use_transactional_tests = false

  def probe_role = "receipt_probe"

  RECEIPT_REFERENCES = [
    [ "finance_titles", "fk_finance_titles_receipt_same_organization" ],
    [ "purchasing_receipt_lines", "fk_purchasing_receipt_lines_receipt_same_order" ],
    [ "purchasing_receipt_lines", "fk_purchasing_receipt_lines_receipt_same_warehouse" ]
  ].freeze
  RECEIPT_LINE_REFERENCES = [ [ "inventory_movements", "fk_inventory_movements_receipt_line_same_balance" ] ].freeze

  before do
    @organization = create(:organization)
    @actor = create(:user, email: "actor-#{SecureRandom.hex(8)}@alicerce.example")
    set_current_tenant(@organization)
    supplier = supplier_for(@organization)
    product = orderable_product(@organization, sku: "CIM-001")
    order = approved_order!(organization: @organization, supplier:, actor: @actor, lines: [ line_input(product, quantity: "10", unit_price_cents: 1_000) ])
    @receipt = Purchasing::ReceiveGoods.call(
      organization: @organization, actor: @actor, order:, warehouse: create(:warehouse, organization: @organization),
      lines: [ { order_line_id: order.lines.sole.id, quantity: "4" } ], received_on: Time.current.in_time_zone(@organization.time_zone).to_date.to_s,
      idempotency_key: SecureRandom.uuid, request_digest: SecureRandom.hex(16)
    ).value
  end

  around do |example|
    with_owner_connection do |owner|
      owner.exec(<<~SQL)
        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{probe_role}') THEN CREATE ROLE #{probe_role} NOLOGIN; END IF;
        END $$;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON purchasing_receipts, purchasing_receipt_lines TO #{probe_role};
        GRANT #{probe_role} TO CURRENT_USER;
      SQL
      @owner = owner
      example.run
    ensure
      owner.exec("DROP OWNED BY #{probe_role}; DROP ROLE IF EXISTS #{probe_role}")
    end
  end

  # A table other tables point at cannot be truncated at all, so before the
  # trigger is ever reached the foreign keys are dropped inside the transaction
  # (rolled back with it), which leaves the trigger the only thing in the way.
  def as_probe(statement, dropping: [])
    @owner.exec("BEGIN")
    dropping.each { |table, constraint| @owner.exec("ALTER TABLE #{table} DROP CONSTRAINT #{constraint}") }
    @owner.exec("SET LOCAL ROLE #{probe_role}")
    @owner.exec("SELECT set_config('app.organization_id', '#{@organization.id}', true)")
    @owner.exec(statement)
  ensure
    @owner.exec("ROLLBACK")
  end

  it "refuses an UPDATE, a DELETE and a TRUNCATE of a receipt" do
    expect { as_probe("UPDATE purchasing_receipts SET total_cents = 1 WHERE id = #{@receipt.id}") }
      .to raise_error(PG::RaiseException, /purchasing_receipts is append-only: UPDATE is not permitted/)
    expect { as_probe("DELETE FROM purchasing_receipts WHERE id = #{@receipt.id}") }
      .to raise_error(PG::RaiseException, /purchasing_receipts is append-only: DELETE is not permitted/)
    expect { as_probe("TRUNCATE purchasing_receipts", dropping: RECEIPT_REFERENCES) }
      .to raise_error(PG::RaiseException, /purchasing_receipts is append-only: TRUNCATE is not permitted/)
  end

  it "refuses an UPDATE, a DELETE and a TRUNCATE of a receipt line" do
    line_id = @receipt.lines.sole.id

    expect { as_probe("UPDATE purchasing_receipt_lines SET net_cents = 1, gross_cents = 1 WHERE id = #{line_id}") }
      .to raise_error(PG::RaiseException, /purchasing_receipt_lines is append-only: UPDATE is not permitted/)
    expect { as_probe("DELETE FROM purchasing_receipt_lines WHERE id = #{line_id}") }
      .to raise_error(PG::RaiseException, /purchasing_receipt_lines is append-only: DELETE is not permitted/)
    expect { as_probe("TRUNCATE purchasing_receipt_lines", dropping: RECEIPT_LINE_REFERENCES) }
      .to raise_error(PG::RaiseException, /purchasing_receipt_lines is append-only: TRUNCATE is not permitted/)
  end

  it "refuses a deletion that would leave a title's installments short of its total, even from a role that may delete" do
    title_id = @receipt.title.id

    @owner.exec("BEGIN")
    @owner.exec("DELETE FROM finance_installments WHERE title_id = #{title_id}")
    expect { @owner.exec("SET CONSTRAINTS ALL IMMEDIATE") }.to raise_error(PG::RaiseException, /add up to 0, not to its total of/)
  ensure
    @owner.exec("ROLLBACK")
  end
end

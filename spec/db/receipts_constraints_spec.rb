require "rails_helper"

RSpec.describe "Receipts, titles and receipt movements: constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:product) { orderable_product(organization, sku: "CIM-001") }
  let(:order) { approved_order!(organization:, supplier:, actor:, lines: [ line_input(product, quantity: "10", unit_price_cents: 1_000) ], installments: 2) }
  let(:receipt) do
    Purchasing::ReceiveGoods.call(
      organization:, actor:, order:, warehouse:, lines: [ { order_line_id: order.lines.sole.id, quantity: "4" } ],
      received_on: Time.current.in_time_zone(organization.time_zone).to_date.to_s, idempotency_key: SecureRandom.uuid,
      request_digest: SecureRandom.hex(16)
    ).value
  end

  # Everything is created up front: a record first built inside an expectation's
  # savepoint loses its id when that savepoint rolls back.
  before do
    set_current_tenant(organization)
    receipt
  end

  def insert_receipt(org: organization, order_id: order.id, warehouse_id: warehouse.id, number: 99, status: "posted", total: 100, currency: "BRL")
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO purchasing_receipts (organization_id, number, order_id, warehouse_id, received_on, total_cents, status, currency, created_by_user_id, created_at)
        VALUES (#{org.id}, #{number}, #{order_id}, #{warehouse_id}, current_date, #{total}, '#{status}', '#{currency}', #{actor.id}, now())
      SQL
    end
  end

  def insert_receipt_line(receipt_id: receipt.id, order_id: order.id, order_line_id: order.lines.sole.id, product_id: product.id, quantity: 1, stock: 1,
                          gross: 1_000, discount: 0, net: 1_000, bp: 0)
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO purchasing_receipt_lines (organization_id, receipt_id, order_id, order_line_id, product_id, product_sku, product_name,
          purchase_unit_code, stock_unit_code, factor, unit_price_cents, discount_bp, quantity, stock_quantity, gross_cents, discount_cents, net_cents, created_at)
        VALUES (#{organization.id}, #{receipt_id}, #{order_id}, #{order_line_id}, #{product_id}, 'S', 'P', 'SC', 'UN', 1, 1000, #{bp}, #{quantity}, #{stock},
                #{gross}, #{discount}, #{net}, now())
      SQL
    end
  end

  def insert_title(org: organization, kind: "payable", receipt_id: nil, partner: supplier, total: 100, status: "open")
    receipt_sql = receipt_id || "NULL"
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO finance_titles (organization_id, kind, partner_id, partner_name, receipt_id, total_cents, status, created_at, updated_at)
        VALUES (#{org.id}, '#{kind}', #{partner.id}, 'Fornecedor', #{receipt_sql}, #{total}, '#{status}', now(), now())
      SQL
    end
  end

  def insert_installment(title_id: receipt.title.id, number: 9, amount: 100, settled: 0)
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO finance_installments (organization_id, title_id, number, due_on, amount_cents, settled_cents, created_at, updated_at)
        VALUES (#{organization.id}, #{title_id}, #{number}, current_date, #{amount}, #{settled}, now(), now())
      SQL
    end
  end

  def insert_movement(kind: "receipt", reason: nil, quantity: 5, receipt_line_id: "NULL")
    reason_sql = reason ? "'#{reason}'" : "NULL"
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO inventory_movements (organization_id, product_id, warehouse_id, kind, quantity, value_cents, on_hand_after, value_after_cents,
                                         reason, receipt_line_id, actor_user_id, created_at)
        VALUES (#{organization.id}, #{product.id}, #{warehouse.id}, '#{kind}', #{quantity}, 500, 5, 500, #{reason_sql}, #{receipt_line_id}, #{actor.id}, now())
      SQL
    end
  end

  describe "purchasing_receipts" do
    it "numbers each organization's receipts once, and knows one state and one currency" do
      expect { insert_receipt(number: 100) }.not_to raise_error
      expect { insert_receipt(number: 100) }.to raise_error(ActiveRecord::RecordNotUnique, /index_purchasing_receipts_on_organization_id_and_number/)
      expect { insert_receipt(number: 101, status: "reversed") }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipts_status_valid/)
      expect { insert_receipt(number: 102, currency: "USD") }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipts_currency_brl/)
      expect { insert_receipt(number: 103, total: -1) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipts_total_range/)
    end

    it "refuses an order or a warehouse of another organization, at the composite foreign key" do
      set_current_tenant(other_organization)
      foreign_supplier = supplier_for(other_organization)
      foreign_order = approved_order!(organization: other_organization, supplier: foreign_supplier, actor:,
        lines: [ line_input(orderable_product(other_organization, sku: "X-1"), quantity: "1", unit_price_cents: 100) ])
      foreign_warehouse = create(:warehouse, organization: other_organization)
      set_current_tenant(organization)

      expect { insert_receipt(order_id: foreign_order.id) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_receipts_order_same_organization/)
      expect { insert_receipt(warehouse_id: foreign_warehouse.id) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_receipts_warehouse_same_organization/)
    end

    it "hides another organization's receipt and refuses to insert one for it (row level security)" do
      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM purchasing_receipts").to_i).to eq(0)
      expect { insert_receipt(number: 200) }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    it "is append-only: the app role holds no UPDATE, DELETE or TRUNCATE on the receipt or its lines, and both keep the second layer" do
      %w[purchasing_receipts purchasing_receipt_lines].each do |table|
        privileges = %w[SELECT INSERT UPDATE DELETE TRUNCATE].to_h do |privilege|
          [ privilege, connection.select_value("SELECT has_table_privilege(current_user, '#{table}', '#{privilege}')") ]
        end
        expect(privileges).to eq("SELECT" => true, "INSERT" => true, "UPDATE" => false, "DELETE" => false, "TRUNCATE" => false)
        expect(connection.select_values("SELECT tgname FROM pg_trigger WHERE tgrelid = '#{table}'::regclass AND NOT tgisinternal"))
          .to contain_exactly("#{table}_append_only", "#{table}_no_truncate")
      end
    end

    it "is read-only at the model too" do
      expect { receipt.update!(supplier_invoice_number: "edited") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { receipt.lines.first.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe "purchasing_receipt_lines" do
    it "takes an order line at most once per receipt" do
      expect { insert_receipt_line }.to raise_error(ActiveRecord::RecordNotUnique, /index_purchasing_receipt_lines_on_receipt_and_order_line/)
    end

    it "belongs to the receipt's own order: a line of another order, or an order id that is not the receipt's, is refused" do
      other = approved_order!(organization:, supplier:, actor:, lines: [ line_input(product, quantity: "3", unit_price_cents: 100) ])

      expect { insert_receipt_line(order_id: other.id, order_line_id: other.lines.sole.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_receipt_lines_receipt_same_order/)
      expect { insert_receipt_line(order_line_id: other.lines.sole.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_receipt_lines_order_line_same_order/)
    end

    it "moves stock and keeps net equal to gross minus discount" do
      other = approved_order!(organization:, supplier:, actor:, lines: [ line_input(product, quantity: "3", unit_price_cents: 100) ])
      insert_receipt(order_id: other.id, number: 300)
      receipt_id = connection.select_value("SELECT id FROM purchasing_receipts WHERE number = 300").to_i

      args = { receipt_id:, order_id: other.id, order_line_id: other.lines.sole.id }
      expect { insert_receipt_line(**args, quantity: 0) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipt_lines_moves_stock/)
      expect { insert_receipt_line(**args, stock: 0) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipt_lines_moves_stock/)
      expect { insert_receipt_line(**args, gross: 1_000, discount: 100, net: 1_000) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipt_lines_amounts_consistent/)
      expect { insert_receipt_line(**args, gross: 100, discount: 200, net: -100) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipt_lines_amounts_consistent/)
      expect { insert_receipt_line(**args, bp: 10_001) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_receipt_lines_discount_range/)
      expect { insert_receipt_line(**args) }.not_to raise_error
    end
  end

  describe "finance_titles" do
    it "gives a receipt at most one title, and a payable always has its receipt" do
      expect { insert_title(receipt_id: receipt.id) }.to raise_error(ActiveRecord::RecordNotUnique, /index_finance_titles_on_receipt_id/)
      expect { insert_title(receipt_id: nil) }.to raise_error(ActiveRecord::StatementInvalid, /finance_titles_payable_has_a_receipt/)
      expect { insert_title(kind: "receivable") }.not_to raise_error
    end

    it "is worth something and knows its kinds and states" do
      expect { insert_title(kind: "receivable", total: 0) }.to raise_error(ActiveRecord::StatementInvalid, /finance_titles_total_range/)
      expect { insert_title(kind: "loan") }.to raise_error(ActiveRecord::StatementInvalid, /finance_titles_kind_valid/)
      expect { insert_title(kind: "receivable", status: "paid") }.to raise_error(ActiveRecord::StatementInvalid, /finance_titles_status_valid/)
    end

    it "refuses a partner of another organization, at the composite foreign key" do
      set_current_tenant(other_organization)
      foreign = supplier_for(other_organization)
      set_current_tenant(organization)

      expect { insert_title(kind: "receivable", partner: foreign) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_finance_titles_partner_same_organization/)
    end

    it "hides another organization's title (row level security)" do
      set_current_tenant(other_organization)

      expect(connection.select_value("SELECT count(*) FROM finance_titles").to_i).to eq(0)
      expect(connection.select_value("SELECT count(*) FROM finance_installments").to_i).to eq(0)
    end
  end

  describe "finance_installments" do
    it "numbers each title's installments once, and none is worth nothing or settled beyond its amount" do
      expect { insert_installment(number: 1) }.to raise_error(ActiveRecord::RecordNotUnique, /index_finance_installments_on_title_and_number/)
      expect { insert_installment(amount: 0) }.to raise_error(ActiveRecord::StatementInvalid, /finance_installments_amount_positive/)
      expect { insert_installment(settled: 101) }.to raise_error(ActiveRecord::StatementInvalid, /finance_installments_settled_within_amount/)
      expect { insert_installment(number: 0) }.to raise_error(ActiveRecord::StatementInvalid, /finance_installments_number_positive/)
      expect { insert_installment }.not_to raise_error
    end
  end

  describe "the installments of a title" do
    def within_immediate_constraints
      connection.transaction(requires_new: true) do
        connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
        yield
      end
    end

    it "must add up to the title's total, checked when the transaction commits (a title with no installments included)" do
      expect { within_immediate_constraints { insert_installment(number: 9, amount: 1) } }
        .to raise_error(ActiveRecord::StatementInvalid, /add up to \d+, not to its total of/)
      expect { within_immediate_constraints { insert_title(kind: "receivable", total: 500) } }
        .to raise_error(ActiveRecord::StatementInvalid, /add up to 0, not to its total of 500/)
    end

    it "lets a title and its installments be written in either order, so long as they agree at commit" do
      expect do
        connection.transaction(requires_new: true) do
          insert_title(kind: "receivable", total: 300)
          title_id = connection.select_value("SELECT max(id) FROM finance_titles").to_i
          insert_installment(title_id:, number: 1, amount: 100)
          insert_installment(title_id:, number: 2, amount: 200)
          connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
        end
      end.not_to raise_error
    end

    it "keeps what a title and an installment were created with, and lets only the settled amount and the status move" do
      title_id = receipt.title.id
      installment_id = receipt.title.installments.first.id

      expect { connection.transaction(requires_new: true) { connection.execute("UPDATE finance_titles SET total_cents = 1 WHERE id = #{title_id}") } }
        .to raise_error(ActiveRecord::StatementInvalid, /a title's kind, partner, receipt and total cannot be changed/)
      expect { connection.transaction(requires_new: true) { connection.execute("UPDATE finance_titles SET partner_id = partner_id + 1 WHERE id = #{title_id}") } }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect { connection.transaction(requires_new: true) { connection.execute("UPDATE finance_installments SET amount_cents = 1 WHERE id = #{installment_id}") } }
        .to raise_error(ActiveRecord::StatementInvalid, /cannot be changed/)
      expect { connection.transaction(requires_new: true) { connection.execute("UPDATE finance_installments SET settled_cents = 1 WHERE id = #{installment_id}") } }
        .not_to raise_error
    end

    it "cannot be deleted by the app role: a title is closed by its status" do
      privileges = %w[SELECT INSERT UPDATE DELETE].to_h do |privilege|
        [ privilege, connection.select_value("SELECT has_table_privilege(current_user, 'finance_titles', '#{privilege}')") ]
      end

      expect(privileges).to eq("SELECT" => true, "INSERT" => true, "UPDATE" => true, "DELETE" => false)
      expect(connection.select_value("SELECT has_table_privilege(current_user, 'finance_installments', 'DELETE')")).to be(false)
    end
  end

  describe "inventory_movements of a receipt" do
    let(:line_id) { receipt.lines.sole.id }

    it "has a positive quantity, no reason and its line, and only a receipt has a line" do
      expect { insert_movement(receipt_line_id: "NULL") }.to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_receipt_shape/)
      expect { insert_movement(reason: "count", receipt_line_id: 0) }.to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_receipt_shape/)
      expect { insert_movement(quantity: 0, receipt_line_id: 0) }.to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_receipt_shape/)
      expect { insert_movement(kind: "adjustment", reason: "count", receipt_line_id: line_id) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_only_receipts_have_a_line/)
      expect { insert_movement(kind: "sale") }.to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_kind_valid/)
    end

    it "lets a receipt line enter stock once" do
      expect { insert_movement(receipt_line_id: line_id) }.to raise_error(ActiveRecord::RecordNotUnique, /index_inventory_movements_on_receipt_line_id/)
    end

    it "points at a receipt line of its own organization only" do
      expect { insert_movement(receipt_line_id: 0) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_inventory_movements_receipt_line_same_organization/)
    end
  end
end

require "rails_helper"

RSpec.describe Purchasing::ReceiveGoods do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization) }
  let(:warehouse) { create(:warehouse, organization:) }
  let(:cimento) { orderable_product(organization, sku: "CIM-001", name: "Cimento") }
  let(:tijolo) { orderable_product(organization, sku: "TIJ-001", name: "Tijolo", purchase_unit_code: "MIL", factor: "1000") }
  let(:cement_lines) { [ line_input(cimento, quantity: "200", unit_price_cents: 3_250, discount_bp: 200) ] }
  let(:order) { approved_order!(organization:, supplier:, actor:, lines: cement_lines, installments: 2) }

  before { set_current_tenant(organization) }

  def today = Time.current.in_time_zone(organization.time_zone).to_date

  def item(line, quantity) = { order_line_id: line.id, quantity: }

  def receive_goods(order, items, received_on: today, key: SecureRandom.uuid, warehouse: self.warehouse, invoice: nil)
    described_class.call(
      organization:, actor:, order:, warehouse:, lines: items, received_on: received_on.to_s, supplier_invoice_number: invoice,
      idempotency_key: key,
      request_digest: Idempotency.digest(method: "POST", path: "/purchase_orders/#{order.id}/receipts", params: { lines: items, received_on: received_on.to_s })
    )
  end

  def balance_of(product) = Inventory::Balance.find_by!(product_id: product.id, warehouse_id: warehouse.id)

  def expect_ledger_to_add_up(product)
    movements = Inventory::Movement.where(product_id: product.id, warehouse_id: warehouse.id)
    expect(movements.sum(:quantity)).to eq(balance_of(product).on_hand)
    expect(movements.sum(:value_cents)).to eq(balance_of(product).value_cents)
  end

  def nothing_was_written
    expect([ Purchasing::Receipt.count, Purchasing::ReceiptLine.count, Inventory::Movement.count, Finance::Title.count, Finance::Installment.count ]).to all(eq(0))
  end

  describe "a partial receipt, then the rest (ADR 0017's worked example)" do
    it "takes 120 of 200 bags: stock in at the net cost, a payable in the order's installments, the order partially received" do
      result = receive_goods(order, [ item(order.lines.sole, "120") ], invoice: "NF 1234")

      expect(result).to be_success
      receipt = result.value
      expect(receipt).to have_attributes(number: 1, order_id: order.id, warehouse_id: warehouse.id, received_on: today, total_cents: 382_200,
        status: "posted", supplier_invoice_number: "NF 1234", created_by_user_id: actor.id)
      expect(receipt.lines.sole).to have_attributes(quantity: BigDecimal("120"), stock_quantity: BigDecimal("120"), gross_cents: 390_000,
        discount_cents: 7_800, net_cents: 382_200, unit_price_cents: 3_250, discount_bp: 200, product_sku: "CIM-001", purchase_unit_code: "SC")
      expect(balance_of(cimento)).to have_attributes(on_hand: BigDecimal("120"), value_cents: 382_200, last_unit_cost: BigDecimal("3185"))
      expect(receipt.lines.sole.movement).to have_attributes(kind: "receipt", quantity: BigDecimal("120"), value_cents: 382_200, reason: nil,
        on_hand_after: BigDecimal("120"), value_after_cents: 382_200, actor_user_id: actor.id)
      expect(order.reload).to have_attributes(status: "partially_received")
      expect(order.lines.sole).to have_attributes(received_quantity: BigDecimal("120"), received_stock_quantity: BigDecimal("120"),
        received_gross_cents: 390_000, received_discount_cents: 7_800)
      title = receipt.title
      expect(title).to have_attributes(kind: "payable", partner_id: supplier.id, partner_name: supplier.name, total_cents: 382_200, status: "open")
      expect(title.installments.map { |i| [ i.number, i.amount_cents, i.due_on ] }).to eq([ [ 1, 191_100, today + 30 ], [ 2, 191_100, today + 60 ] ])
      event = Audit::Event.where(action: "goods_received").sole
      expect(event.field_changes).to include("number" => 1, "total_cents" => 382_200, "order_status" => { "from" => "approved", "to" => "partially_received" },
        "supplier_invoice_number" => "changed")
      expect(event.field_changes.to_s).not_to include("NF 1234")
      expect_ledger_to_add_up(cimento)
    end

    it "takes the remaining 80: what is left of the gross and the discount, closing the order, and the two payables add up to the order" do
      line = order.lines.sole
      receive_goods(order, [ item(line, "120") ])

      result = receive_goods(order, [ item(line, "80") ])

      expect(result).to be_success
      expect(result.value).to have_attributes(number: 2, total_cents: 254_800)
      expect(result.value.lines.sole).to have_attributes(gross_cents: 260_000, discount_cents: 5_200, net_cents: 254_800)
      expect(order.reload).to have_attributes(status: "received")
      expect(order.lines.sole).to have_attributes(received_quantity: BigDecimal("200"), received_gross_cents: 650_000, received_discount_cents: 13_000)
      expect(Finance::Title.sum(:total_cents)).to eq(order.total_cents)
      expect(Purchasing::ReceiptLine.sum(:net_cents)).to eq(order.total_cents)
      expect(balance_of(cimento)).to have_attributes(on_hand: BigDecimal("200"), value_cents: 637_000)
      expect_ledger_to_add_up(cimento)
    end

    it "leaves nothing behind in any number of parts: 200 bags at R$ 32,25 in odd pieces never make a negative amount and sum to the line" do
      lines = [ line_input(cimento, quantity: "200", unit_price_cents: 3_225, discount_bp: 200) ]
      odd = approved_order!(organization:, supplier:, actor:, lines:)
      line = odd.lines.sole

      %w[33.333 0.001 41.667 50 74.999].each do |quantity|
        result = receive_goods(odd, [ item(line, quantity) ])
        expect(result).to be_success
        expect(result.value.lines.sole).to have_attributes(gross_cents: be >= 0, discount_cents: be >= 0, net_cents: be >= 0)
      end

      line.reload
      expect(Purchasing::ReceiptLine.sum(:gross_cents)).to eq(line.gross_cents)
      expect(Purchasing::ReceiptLine.sum(:discount_cents)).to eq(line.discount_cents)
      expect(Purchasing::ReceiptLine.sum(:net_cents)).to eq(line.net_cents)
      expect(Purchasing::ReceiptLine.sum(:stock_quantity)).to eq(BigDecimal("200"))
      expect(odd.reload.status).to eq("received")
      expect_ledger_to_add_up(cimento)
    end
  end

  describe "unit conversion" do
    it "enters bricks bought by the thousand as single bricks at their unit cost" do
      bricks = approved_order!(organization:, supplier:, actor:, lines: [ line_input(tijolo, quantity: "5", unit_price_cents: 84_990) ])

      result = receive_goods(bricks, [ item(bricks.lines.sole, "5") ])

      expect(result.value.lines.sole).to have_attributes(quantity: BigDecimal("5"), stock_quantity: BigDecimal("5000"), net_cents: 424_950,
        factor: BigDecimal("1000"), purchase_unit_code: "MIL", stock_unit_code: "UN")
      expect(balance_of(tijolo)).to have_attributes(on_hand: BigDecimal("5000"), value_cents: 424_950, last_unit_cost: BigDecimal("84.99"))
    end

    it "refuses a line that would enter no stock at all" do
      tiny = orderable_product(organization, sku: "TNY-001", purchase_unit_code: "KG", factor: "0.0004")
      order = approved_order!(organization:, supplier:, actor:, lines: [ line_input(tiny, quantity: "1", unit_price_cents: 1_000) ])

      result = receive_goods(order, [ item(order.lines.sole, "1") ])

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq("lines.0.quantity" => [ "quantity_too_small" ])
      nothing_was_written
    end
  end

  describe "the payable" do
    it "splits an amount that does not divide evenly with the extra cent first, and never makes a zero installment" do
      uneven = approved_order!(organization:, supplier:, actor:, installments: 3, first_due_days: 10, interval_days: 15,
        lines: [ line_input(cimento, quantity: "1", unit_price_cents: 382_201) ])

      installments = receive_goods(uneven, [ item(uneven.lines.sole, "1") ]).value.title.installments

      expect(installments.map(&:amount_cents)).to eq([ 127_401, 127_400, 127_400 ])
      expect(installments.map(&:due_on)).to eq([ today + 10, today + 25, today + 40 ])

      pennies = approved_order!(organization:, supplier:, actor:, installments: 5, lines: [ line_input(cimento, quantity: "1", unit_price_cents: 2) ])
      expect(receive_goods(pennies, [ item(pennies.lines.sole, "1") ]).value.title.installments.map(&:amount_cents)).to eq([ 1, 1 ])
    end

    it "leaves the last cost alone when a line's cost rounds to zero, as it does for a free one" do
      pallets = orderable_product(organization, sku: "PAL-001", purchase_unit_code: "FD", factor: "3000000")
      costly = approved_order!(organization:, supplier:, actor:, lines: [ line_input(pallets, quantity: "1", unit_price_cents: 10_000_000) ])
      receive_goods(costly, [ item(costly.lines.sole, "1") ])
      expect(balance_of(pallets).last_unit_cost).to eq(BigDecimal("3.333333"))

      penny = approved_order!(organization:, supplier:, actor:, lines: [ line_input(pallets, quantity: "1", unit_price_cents: 1) ])
      result = receive_goods(penny, [ item(penny.lines.sole, "1") ])

      expect(result.value.lines.sole).to have_attributes(stock_quantity: BigDecimal("3000000"), net_cents: 1)
      expect(balance_of(pallets)).to have_attributes(on_hand: BigDecimal("6000000"), value_cents: 10_000_001, last_unit_cost: BigDecimal("3.333333"))
      expect_ledger_to_add_up(pallets)
    end

    it "opens no title for a receipt worth nothing, and a free line leaves the last cost alone" do
      cheap = approved_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "10", unit_price_cents: 1) ])
      line = cheap.lines.sole
      receive_goods(cheap, [ item(line, "5") ])
      expect(balance_of(cimento).last_unit_cost).to eq(BigDecimal("1"))

      result = receive_goods(cheap, [ item(line, "0.001") ])

      expect(result).to be_success
      expect(result.value).to have_attributes(total_cents: 0, title: nil)
      expect(result.value.lines.sole).to have_attributes(stock_quantity: BigDecimal("0.001"), net_cents: 0)
      expect(Finance::Title.count).to eq(1)
      expect(balance_of(cimento)).to have_attributes(on_hand: BigDecimal("5.001"), value_cents: 5, last_unit_cost: BigDecimal("1"))
      expect_ledger_to_add_up(cimento)
    end
  end

  describe "several lines" do
    it "posts two lines of one product one after the other, so the ledger chains and adds up" do
      two = approved_order!(organization:, supplier:, actor:, lines: [
        line_input(cimento, quantity: "10", unit_price_cents: 3_000), line_input(cimento, quantity: "5", unit_price_cents: 3_500)
      ])
      first, second = two.lines.to_a

      result = receive_goods(two, [ item(first, "10"), item(second, "5") ])

      expect(result).to be_success
      expect(result.value.total_cents).to eq(47_500)
      expect(Inventory::Movement.order(:id).map(&:on_hand_after)).to eq([ BigDecimal("10"), BigDecimal("15") ])
      expect(balance_of(cimento)).to have_attributes(on_hand: BigDecimal("15"), value_cents: 47_500, last_unit_cost: BigDecimal("3500"))
      expect(two.reload.status).to eq("received")
      expect_ledger_to_add_up(cimento)
      result.value.lines.each do |receipt_line|
        expect(receipt_line.movement).to have_attributes(kind: "receipt", product_id: receipt_line.product_id, warehouse_id: warehouse.id,
          quantity: receipt_line.stock_quantity, value_cents: receipt_line.net_cents)
        expect(receipt_line.warehouse_id).to eq(warehouse.id)
      end
    end

    it "keeps the order partially received while any line has something left" do
      two = approved_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "10"), line_input(tijolo, quantity: "2") ])

      receive_goods(two, [ item(two.lines.first, "10") ])

      expect(two.reload.status).to eq("partially_received")
    end
  end

  describe "what it refuses" do
    it "more than what is left, with no tolerance, and writes nothing, not even a number" do
      line = order.lines.sole

      result = receive_goods(order, [ item(line, "200.001") ])

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq("lines.0.quantity" => [ "over_receipt" ])
      nothing_was_written
      expect(order.reload.status).to eq("approved")
      expect(receive_goods(order, [ item(line, "200") ]).value.number).to eq(1)
    end

    it "more lines than a receipt takes, so it never holds the receipt counter for long" do
      many = approved_order!(organization:, supplier:, actor:, lines: Array.new(Purchasing::Receipt::MAX_LINES + 1) { line_input(cimento, quantity: "1") })

      result = receive_goods(many, many.lines.map { |line| item(line, "1") })

      expect(result.details[:fields]).to eq("lines" => [ "too_many" ])
      nothing_was_written
    end

    it "stock that two lines of one product would together not fit in a balance, though each fits alone" do
      big = approved_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "600000000000", unit_price_cents: 1), line_input(cimento, quantity: "600000000000", unit_price_cents: 1) ])

      result = receive_goods(big, big.lines.map { |line| item(line, "600000000000") })

      expect(result.details[:fields]).to eq("lines.1.quantity" => [ "too_large" ])
      nothing_was_written
    end

    it "a cost per unit that would not fit the last cost column" do
      dear = approved_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "0.001", unit_price_cents: 10**15) ])

      result = receive_goods(dear, [ item(dear.lines.sole, "0.001") ])

      expect(result.details[:fields]).to eq("lines.0.quantity" => [ "too_large" ])
      nothing_was_written
    end

    it "the same order line twice in one request" do
      line = order.lines.sole

      result = receive_goods(order, [ item(line, "10"), item(line, "20") ])

      expect(result.details[:fields]).to eq("lines.1.order_line_id" => [ "duplicate_line" ])
      nothing_was_written
    end

    it "a line of another order, or one that does not exist" do
      other = approved_order!(organization:, supplier:, actor:, lines: cement_lines)

      result = receive_goods(order, [ item(other.lines.sole, "10"), { order_line_id: 0, quantity: "1" } ])

      expect(result.details[:fields]).to eq("lines.0.order_line_id" => [ "not_found" ], "lines.1.order_line_id" => [ "not_found" ])
      nothing_was_written
    end

    it "bad input, all at once: no lines, a zero, a float, too many decimals, junk" do
      line = order.lines.sole

      expect(receive_goods(order, []).details[:fields]).to eq("lines" => [ "blank" ])
      expect(receive_goods(order, "lines").details[:fields]).to eq("lines" => [ "blank" ])
      result = receive_goods(order, [ item(line, "0"), item(line, 1.5), item(line, "1.0001"), "x", { order_line_id: "abc", quantity: "-1" } ])
      expect(result.details[:fields]).to eq(
        "lines.0.quantity" => [ "must_be_positive" ], "lines.1.quantity" => [ "not_a_number" ],
        "lines.2.quantity" => [ "too_many_decimals" ], "lines.3" => [ "invalid" ], "lines.4.order_line_id" => [ "not_a_number" ],
        "lines.4.quantity" => [ "negative" ]
      )
      nothing_was_written
    end

    it "an order that is not approved or partially received" do
      draft = create_order!(organization:, supplier:, actor:, lines: cement_lines)
      cancelled = approved_order!(organization:, supplier:, actor:, lines: cement_lines)
      Purchasing::CancelOrder.call(order: cancelled, actor:)
      done = approved_order!(organization:, supplier:, actor:, lines: [ line_input(cimento, quantity: "1") ])
      receive_goods(done, [ item(done.lines.sole, "1") ])

      [ draft, cancelled, done ].each do |refused|
        result = receive_goods(refused, [ item(refused.lines.sole, "1") ])
        expect(result.error).to eq(:invalid_transition)
      end
      expect(Purchasing::Receipt.count).to eq(1)
    end

    it "decides from the locked row, not from the instance it was handed (a stale order)" do
      stale = Purchasing::Order.find(order.id)
      Purchasing::CancelOrder.call(order:, actor:)

      expect(receive_goods(stale, [ item(stale.lines.sole, "1") ]).error).to eq(:invalid_transition)
      nothing_was_written
    end

    it "a warehouse that is not in use" do
      warehouse.update!(active: false)

      result = receive_goods(order, [ item(order.lines.sole, "1") ])

      expect(result.details[:fields]).to eq("warehouse_id" => [ "inactive" ])
    end

    it "an invoice number that is not text or is too long, and a bad key" do
      line = order.lines.sole

      expect(receive_goods(order, [ item(line, "1") ], invoice: "x" * 61).details[:fields]).to eq("supplier_invoice_number" => [ "too_long" ])
      expect(receive_goods(order, [ item(line, "1") ], invoice: [ "a" ]).details[:fields]).to eq("supplier_invoice_number" => [ "invalid" ])
      expect(receive_goods(order, [ item(line, "1") ], key: "short").details[:fields]).to eq("idempotency_key" => [ "invalid" ])
    end

    it "an invoice number that is not one: characters outside the usual, or a long run of digits such as an NF-e access key" do
      line = order.lines.sole
      access_key = "29260912345678000199550010000012341000012345"

      [ access_key, "NF #123", "NF\n1", "-1234", "1" * 16 ].each do |invoice|
        expect(receive_goods(order, [ item(line, "1") ], invoice:).details[:fields]).to eq("supplier_invoice_number" => [ "invalid" ]), "expected #{invoice.inspect} to be refused"
      end
      expect(receive_goods(order, [ item(line, "1") ], invoice: "NF 1234/1-A.2")).to be_success
    end

    it "a balance already below zero, which a receipt does not settle yet" do
      Inventory::Balance.create!(organization:, product: cimento, warehouse:, on_hand: BigDecimal("-3"), value_cents: -900, negative_allowance: BigDecimal("10"))

      result = receive_goods(order, [ item(order.lines.sole, "10") ])

      expect(result.error).to eq(:negative_balance)
      nothing_was_written
      expect(balance_of(cimento).on_hand).to eq(BigDecimal("-3"))
    end

    it "stock that would not fit a balance" do
      Inventory::Balance.create!(organization:, product: cimento, warehouse:, on_hand: BigDecimal("999999999999.000"), value_cents: 100)

      result = receive_goods(order, [ item(order.lines.sole, "1") ])

      expect(result.details[:fields]).to eq("lines.0.quantity" => [ "too_large" ])
      nothing_was_written
    end

    it "a value that would pass what a balance may hold" do
      Inventory::Balance.create!(organization:, product: cimento, warehouse:, on_hand: BigDecimal("1"), value_cents: Inventory::Ledger::VALUE_CAP_CENTS - 10)

      result = receive_goods(order, [ item(order.lines.sole, "1") ])

      expect(result.details[:fields]).to eq("lines.0.quantity" => [ "too_large" ])
    end
  end

  describe "the date" do
    it "is a real day, not in the future in the organization's time zone" do
      line = order.lines.sole

      expect(receive_goods(order, [ item(line, "1") ], received_on: today + 1).details[:fields]).to eq("received_on" => [ "in_the_future" ])
      expect(receive_goods(order, [ item(line, "1") ], received_on: "2026-02-30").details[:fields]).to eq("received_on" => [ "invalid" ])
      expect(receive_goods(order, [ item(line, "1") ], received_on: "26/09/2026").details[:fields]).to eq("received_on" => [ "invalid" ])
      expect(receive_goods(order, [ item(line, "1") ], received_on: "").details[:fields]).to eq("received_on" => [ "blank" ])
    end

    it "is judged by the organization's day, not the server's: 22:00 in Sao Paulo is already the next day in UTC" do
      travel_to Time.utc(2026, 9, 27, 1, 0) do
        fresh = approved_order!(organization:, supplier:, actor:, lines: cement_lines)
        line = fresh.lines.sole

        expect(receive_goods(fresh, [ item(line, "1") ], received_on: "2026-09-27").details[:fields]).to eq("received_on" => [ "in_the_future" ])
        expect(receive_goods(fresh, [ item(line, "1") ], received_on: "2026-09-26")).to be_success
      end
    end

    it "is not before the day the order was approved" do
      travel_to Time.utc(2026, 9, 27, 15, 0) do
        fresh = approved_order!(organization:, supplier:, actor:, lines: cement_lines)
        line = fresh.lines.sole

        expect(receive_goods(fresh, [ item(line, "1") ], received_on: "2026-09-26").details[:fields]).to eq("received_on" => [ "before_approval" ])
        expect(receive_goods(fresh, [ item(line, "1") ], received_on: "2026-09-27")).to be_success
      end
    end
  end

  describe "idempotency (ADR 0005)" do
    it "returns the same receipt for the same key and request, and writes nothing twice" do
      params = [ item(order.lines.sole, "50") ]
      first = receive_goods(order, params, key: "receive-0001")

      again = receive_goods(order, params, key: "receive-0001")

      expect(again).to be_success
      expect(again.value.id).to eq(first.value.id)
      expect([ Purchasing::Receipt.count, Inventory::Movement.count, Finance::Title.count ]).to eq([ 1, 1, 1 ])
      expect(balance_of(cimento).on_hand).to eq(BigDecimal("50"))
    end

    it "replays a request that succeeded even when the warehouse was deactivated since" do
      params = [ item(order.lines.sole, "50") ]
      first = receive_goods(order, params, key: "receive-0009")
      warehouse.update!(active: false)

      again = receive_goods(order, params, key: "receive-0009")

      expect(again).to be_success
      expect(again.value.id).to eq(first.value.id)
    end

    it "refuses the same key for a different request" do
      line = order.lines.sole
      receive_goods(order, [ item(line, "50") ], key: "receive-0001")

      result = receive_goods(order, [ item(line, "60") ], key: "receive-0001")

      expect(result.error).to eq(:idempotency_key_reused)
      expect(Purchasing::Receipt.count).to eq(1)
    end

    it "lets a failed attempt be retried with the same key, since the key rolls back with it" do
      line = order.lines.sole
      failed = receive_goods(order, [ item(line, "500") ], key: "receive-0002")
      expect(failed.error).to eq(:validation_failed)

      expect(receive_goods(order, [ item(line, "500") ], key: "receive-0002").error).to eq(:validation_failed)
      expect(IdempotencyKey.where(key: "receive-0002")).to be_empty
    end
  end

  describe "atomicity (invariant 2: receiving and stock entry go together)" do
    it "rolls back the receipt, the stock, the order and the number when the payable cannot be opened" do
      allow(Finance::Payables).to receive(:open_for).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { receive_goods(order, [ item(order.lines.sole, "120") ], key: "receive-0003") }.to raise_error(ActiveRecord::StatementInvalid)

      nothing_was_written
      expect(Inventory::Balance.where(product_id: cimento.id).sum(:on_hand)).to eq(0)
      expect(order.reload).to have_attributes(status: "approved")
      expect(order.lines.sole.received_quantity).to eq(0)
      expect(IdempotencyKey.where(key: "receive-0003")).to be_empty
      expect(Audit::Event.where(action: "goods_received")).to be_empty
      allow(Finance::Payables).to receive(:open_for).and_call_original
      expect(receive_goods(order, [ item(order.lines.sole, "120") ]).value.number).to eq(1)
    end
  end
end

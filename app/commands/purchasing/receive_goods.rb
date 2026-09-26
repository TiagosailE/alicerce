module Purchasing
  # Receives goods against an approved order (ADR 0017): one receipt for one
  # warehouse, stock in through the ledger, the order's progress, and one payable
  # with its installments, all in one transaction or none of it. A critical write
  # (ADR 0005), so it takes an idempotency key.
  #
  # Order of work follows ADR 0004: lock timeout, idempotency key, the order and
  # then its lines (ascending by id), the balances (ascending by product and
  # warehouse), then every check and every figure worked out in memory from the
  # re-read rows, then the receipt number (the last lock), then the writes. A
  # failing check therefore costs no number and writes nothing, and nothing here
  # calls out of the database while the locks are held.
  #
  # Error codes: :validation_failed (fields "lines", "lines.N.order_line_id",
  # "lines.N.quantity", "received_on", "supplier_invoice_number", "warehouse_id",
  # "idempotency_key"), :invalid_transition (the order is not approved or
  # partially received), :negative_balance (a balance involved is below zero,
  # which a receipt does not settle yet), :idempotency_key_reused,
  # :conflict_retry (lock wait timed out or deadlocked, safe to retry with the
  # same key).
  class ReceiveGoods
    # A room in a balance's numeric(15,3) on hand, in stock units.
    ON_HAND_LIMIT = 10**Purchasing::OrderLine::QUANTITY_INTEGER_DIGITS
    # A cost per stock unit is numeric(19,6): 13 integer digits, 6 places.
    COST_PLACES = 6
    COST_LIMIT = 10**13

    Entry = Data.define(:item, :line, :amounts, :last_unit_cost)
    Running = Struct.new(:on_hand, :value_cents)

    def self.call(...) = new(...).call

    def initialize(organization:, actor:, order:, warehouse:, lines:, received_on:, idempotency_key:, request_digest:,
                   supplier_invoice_number: nil)
      @organization = organization
      @actor = actor
      @order = order
      @warehouse = warehouse
      @inputs = { lines:, received_on:, supplier_invoice_number: }
      @idempotency_key = idempotency_key
      @request_digest = request_digest
    end

    def call
      @input, fields = Purchasing::ReceiptInput.call(**@inputs, time_zone: @organization.time_zone)
      fields["warehouse_id"] = [ "inactive" ] unless @warehouse.active?
      fields["idempotency_key"] = [ "invalid" ] unless Idempotency.valid_key?(@idempotency_key)
      return Result.failure(:validation_failed, fields:) if fields.any?

      result = nil
      ApplicationRecord.transaction do
        ApplicationRecord.lease_connection.execute("SET LOCAL lock_timeout = '3s'")
        result = perform
        raise ActiveRecord::Rollback unless result.success?
      end
      result
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      Result.failure(:conflict_retry)
    end

    private
      def perform
        Idempotency.run(organization: @organization, user: @actor, key: @idempotency_key, request_digest: @request_digest,
                        on_replay: method(:replay)) do |claim|
          receive(claim)
        end
      end

      def receive(claim)
        order = Purchasing::Order.lock("FOR NO KEY UPDATE").find(@order.id)
        return Result.failure(:invalid_transition) unless order.can_transition_to?("received")

        lines = Purchasing::OrderLine.where(order_id: order.id).order(:id).lock("FOR NO KEY UPDATE").index_by(&:id)
        fields = row_errors(order, lines)
        return Result.failure(:validation_failed, fields:) if fields.any?

        balances = lock_balances(lines)
        return Result.failure(:negative_balance) if balances.values.any? { |balance| balance.on_hand.negative? }

        entries, fields = plan(lines, balances)
        return Result.failure(:validation_failed, fields:) if fields.any?

        post(claim, order, lines, balances, entries)
      end

      # What can only be known from the locked rows: each line is this order's,
      # and the day is not before the order was approved.
      def row_errors(order, lines)
        fields = {}
        @input.items.each do |item|
          (fields["lines.#{item.index}.order_line_id"] ||= []) << "not_found" unless lines.key?(item.order_line_id)
        end
        approved_on = order.approved_at.in_time_zone(@organization.time_zone).to_date
        fields["received_on"] = [ "before_approval" ] if @input.received_on < approved_on
        fields
      end

      def lock_balances(lines)
        pairs = @input.items.map { |item| [ lines.fetch(item.order_line_id).product_id, @warehouse.id ] }
        Inventory::Balance.lock_for(organization: @organization, pairs:).index_by(&:product_id)
      end

      # Works out every line, in order, against a running copy of each balance
      # so two lines of one product on the same receipt are judged one after the
      # other, exactly as they will be posted.
      def plan(lines, balances)
        running = balances.transform_values { |balance| Running.new(balance.on_hand, balance.value_cents) }
        fields = {}
        entries = @input.items.filter_map do |item|
          line = lines.fetch(item.order_line_id)
          outcome = entry_for(item, line, running.fetch(line.product_id))
          next outcome if outcome.is_a?(Entry)

          (fields["lines.#{item.index}.quantity"] ||= []) << outcome
          nil
        end
        [ entries, fields ]
      end

      # An Entry, or the name of what is wrong with the line.
      def entry_for(item, line, balance)
        return "over_receipt" if item.quantity > line.remaining_quantity

        amounts = Purchasing::ReceiptMath.call(line:, quantity: item.quantity)
        return "quantity_too_small" unless amounts.stock_quantity.positive?

        on_hand = balance.on_hand + amounts.stock_quantity
        value = balance.value_cents + amounts.net_cents
        cost = last_unit_cost(amounts)
        return "too_large" if on_hand >= ON_HAND_LIMIT || value.abs > Inventory::Ledger::VALUE_CAP_CENTS || (cost && cost >= COST_LIMIT)

        balance.on_hand = on_hand
        balance.value_cents = value
        Entry.new(item:, line:, amounts:, last_unit_cost: cost)
      end

      # The cost of what came in, per stock unit, to the place ADR 0006 names;
      # a free line leaves the last cost alone (nil), so it never wipes it.
      def last_unit_cost(amounts)
        return unless amounts.net_cents.positive?

        scaled = Inventory::Costing.round_half_up(Rational(amounts.net_cents) / amounts.stock_quantity.to_r * 10**COST_PLACES)
        BigDecimal(scaled.to_s) / 10**COST_PLACES
      end

      def post(claim, order, lines, balances, entries)
        total = entries.sum { |entry| entry.amounts.net_cents }
        receipt = Purchasing::Receipt.create!(
          organization: @organization, number: DocumentCounter.next!(organization: @organization, kind: "receipt"),
          order:, warehouse: @warehouse, received_on: @input.received_on, supplier_invoice_number: @input.supplier_invoice_number,
          total_cents: total, created_by_user: @actor
        )
        entries.each { |entry| receive_line(receipt, balances.fetch(entry.line.product_id), entry) }

        from = order.status
        to = lines.each_value.all? { |line| line.received_quantity == line.quantity } ? "received" : "partially_received"
        order.transition_to!(to) unless from == to
        title = Finance::Payables.open_for(receipt:, order:, total_cents: total)
        Audit.record("goods_received", receipt, actor: @actor, changes: audit_changes(receipt, order, from, to, title, entries.size))
        claim.complete!(status: 201, resource: receipt)
        Result.success(receipt)
      end

      def receive_line(receipt, balance, entry)
        line = entry.line
        amounts = entry.amounts
        receipt_line = Purchasing::ReceiptLine.create!(
          organization: @organization, receipt:, order_id: line.order_id, order_line: line, product_id: line.product_id,
          product_sku: line.product_sku, product_name: line.product_name, purchase_unit_code: line.purchase_unit_code,
          stock_unit_code: line.stock_unit_code, factor: line.factor, unit_price_cents: line.unit_price_cents,
          discount_bp: line.discount_bp, quantity: entry.item.quantity, stock_quantity: amounts.stock_quantity,
          gross_cents: amounts.gross_cents, discount_cents: amounts.discount_cents, net_cents: amounts.net_cents
        )
        Inventory::Ledger.post(balance:, kind: "receipt", quantity: amounts.stock_quantity, value_cents: amounts.net_cents,
                               actor: @actor, last_unit_cost: entry.last_unit_cost, receipt_line_id: receipt_line.id)
        line.update!(
          received_quantity: line.received_quantity + entry.item.quantity,
          received_stock_quantity: line.received_stock_quantity + amounts.stock_quantity,
          received_gross_cents: line.received_gross_cents + amounts.gross_cents,
          received_discount_cents: line.received_discount_cents + amounts.discount_cents
        )
      end

      # The supplier's invoice number is typed from a paper document: recorded as
      # changed, without its value (ADR 0010).
      def audit_changes(receipt, order, from, to, title, line_count)
        changes = {
          number: receipt.number, order_id: order.id, warehouse_id: receipt.warehouse_id,
          received_on: receipt.received_on.iso8601, total_cents: receipt.total_cents, lines: line_count,
          order_status: { from:, to: }
        }
        changes[:title_id] = title.id if title
        changes[:supplier_invoice_number] = "changed" if receipt.supplier_invoice_number
        changes
      end

      # The same request retried: the receipt as it is now.
      def replay(record)
        Result.success(Purchasing::Receipt.find(record.resource_id))
      end
  end
end

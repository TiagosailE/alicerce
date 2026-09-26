module Inventory
  # A count adjustment (ADR 0016): sets a product's stock in a warehouse to the
  # quantity actually counted, recording the difference as one ledger movement
  # with a reason. A critical write (ADR 0005), so it takes an idempotency key.
  #
  # A count is an observation made at a moment, so the caller also says what the
  # balance was when it looked (expected_on_hand). If a sale or a receipt moved
  # the balance in between, the difference the operator meant is no longer the
  # difference the balance needs, and applying it would silently undo that
  # movement: the count is refused as :stale instead.
  #
  # Order of work follows ADR 0004: lock timeout, idempotency key, the balance
  # row locked FOR NO KEY UPDATE; every check that depends on the balance
  # happens after that lock, on the re-read values. Nothing here calls out of
  # the database while the lock is held.
  #
  # Error codes: :validation_failed (input; fields "counted_quantity",
  # "expected_on_hand", "reason", "note" and "unit_cost_cents"), :stale (the
  # balance is not what the caller saw; details carry current_on_hand),
  # :negative_balance (the balance is below zero, which an adjustment does not
  # settle yet), :idempotency_key_reused (same key, different request),
  # :conflict_retry (lock wait timed out or deadlocked, safe to retry with the
  # same key).
  class AdjustStock
    QUANTITY_PLACES = 3
    QUANTITY_INTEGER_DIGITS = 12
    UNIT_COST_PLACES = 6
    UNIT_COST_INTEGER_DIGITS = 13

    # status is 201 when a movement was written and 200 when the count matched
    # the balance and nothing was; a replay carries the stored one.
    Adjustment = Data.define(:balance, :movement, :status)

    def self.call(...) = new(...).call

    def initialize(organization:, actor:, product:, warehouse:, counted_quantity:, expected_on_hand:, reason:, idempotency_key:,
                   request_digest:, note: nil, unit_cost_cents: nil)
      @organization = organization
      @actor = actor
      @product = product
      @warehouse = warehouse
      @counted_quantity = counted_quantity
      @expected_on_hand = expected_on_hand
      @reason = reason
      @note = note.presence
      @unit_cost = unit_cost_cents.presence
      @unit_cost_value = nil
      @idempotency_key = idempotency_key
      @request_digest = request_digest
    end

    def call
      invalid = validate_input
      return invalid if invalid

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
          balance = Inventory::Balance.lock_for(organization: @organization, pairs: [ [ @product.id, @warehouse.id ] ]).sole
          adjust(claim, balance)
        end
      end

      def adjust(claim, balance)
        return Result.failure(:stale, current_on_hand: DecimalString.format(balance.on_hand, QUANTITY_PLACES)) if balance.on_hand != @expected
        return Result.failure(:negative_balance) if balance.on_hand.negative?

        delta = @counted - balance.on_hand
        if delta.zero?
          claim.complete!(status: 200, resource: balance)
          return Result.success(Adjustment.new(balance:, movement: nil, status: 200))
        end

        conflict = reason_conflict(balance, delta)
        return conflict if conflict

        valued = delta.positive? ? value_of_increase(balance, delta) : value_of_decrease(balance, delta)
        return valued if valued.is_a?(Result)

        value_cents, last_unit_cost = valued
        unless Inventory::Ledger.fits?(balance, value_cents)
          return Result.failure(:validation_failed, fields: { (@unit_cost_value ? "unit_cost_cents" : "counted_quantity") => [ "too_large" ] })
        end

        movement = Inventory::Ledger.post(balance:, kind: "adjustment", quantity: delta, value_cents:, actor: @actor,
                                          reason: @reason, note: @note, last_unit_cost:)
        Audit.record("stock_adjusted", movement, actor: @actor, changes: audit_changes(movement))
        claim.complete!(status: 201, resource: movement)
        Result.success(Adjustment.new(balance:, movement:, status: 201))
      end

      # The reason states why stock moved, so it must agree with the direction
      # (Movement::DECREASE_ONLY_REASONS), and an opening balance is the first
      # thing a balance ever gets.
      def reason_conflict(balance, delta)
        wrong_way = delta.positive? ? Inventory::Movement::DECREASE_ONLY_REASONS : Inventory::Movement::INCREASE_ONLY_REASONS
        return Result.failure(:validation_failed, fields: { "reason" => [ "incompatible_with_direction" ] }) if wrong_way.include?(@reason)

        return unless @reason == "opening_balance" && Inventory::Movement.exists?(product_id: balance.product_id, warehouse_id: balance.warehouse_id)

        Result.failure(:validation_failed, fields: { "reason" => [ "balance_has_history" ] })
      end

      # A decrease is worth the balance's average cost, and the one that
      # empties the balance takes all the remaining value instead of a rounded
      # share (ADR 0006), so a balance at zero never keeps a residual value.
      def value_of_decrease(balance, delta)
        return Result.failure(:validation_failed, fields: { "unit_cost_cents" => [ "not_applicable" ] }) if @unit_cost_value

        quantity = -delta
        value = if @counted.zero?
          balance.value_cents
        else
          Inventory::Costing.value_at_average_cost(balance.value_cents, quantity, balance.on_hand)
        end
        [ -value, balance.last_unit_cost ]
      end

      # An increase takes the operator's stated cost, which also becomes the
      # last cost; otherwise the current average, when there is one; otherwise
      # the last cost; otherwise it is refused, because stock never enters the
      # books at a made-up cost (ADR 0016). An average of zero (a balance worth
      # less than a cent a unit after rounding) is no average at all.
      def value_of_increase(balance, delta)
        if @unit_cost_value
          [ Inventory::Costing.value_at_unit_cost(delta, @unit_cost_value), @unit_cost_value ]
        elsif balance.on_hand.positive? && balance.value_cents.positive?
          [ Inventory::Costing.value_at_average_cost(balance.value_cents, delta, balance.on_hand), balance.last_unit_cost ]
        elsif balance.last_unit_cost.positive?
          [ Inventory::Costing.value_at_unit_cost(delta, balance.last_unit_cost), balance.last_unit_cost ]
        else
          Result.failure(:validation_failed, fields: { "unit_cost_cents" => [ "required" ] })
        end
      end

      # The note is free text, recorded as changed without its value (ADR 0010).
      def audit_changes(movement)
        changes = {
          product_id: movement.product_id, warehouse_id: movement.warehouse_id, reason: movement.reason,
          quantity: DecimalString.format(movement.quantity, QUANTITY_PLACES), value_cents: movement.value_cents
        }
        changes[:note] = "changed" if movement.note
        changes
      end

      # The same request retried: the stored status and the resource as it is now.
      def replay(record)
        if record.resource_type == Inventory::Movement.name
          movement = Inventory::Movement.find(record.resource_id)
          balance = Inventory::Balance.find_by!(product_id: movement.product_id, warehouse_id: movement.warehouse_id)
        else
          balance = Inventory::Balance.find(record.resource_id)
          movement = nil
        end
        Result.success(Adjustment.new(balance:, movement:, status: record.response_status))
      end

      def validate_input
        fields = {}
        @counted, kind = DecimalString.parse(@counted_quantity, places: QUANTITY_PLACES, integer_digits: QUANTITY_INTEGER_DIGITS)
        fields["counted_quantity"] = [ kind.to_s ] if kind

        @expected, kind = DecimalString.parse(@expected_on_hand, places: QUANTITY_PLACES, integer_digits: QUANTITY_INTEGER_DIGITS,
                                                                 allow_negative: true)
        fields["expected_on_hand"] = [ kind.to_s ] if kind

        if @unit_cost
          @unit_cost_value, kind = DecimalString.parse(@unit_cost, places: UNIT_COST_PLACES, integer_digits: UNIT_COST_INTEGER_DIGITS)
          fields["unit_cost_cents"] = [ kind.to_s ] if kind
        end

        fields["reason"] = [ "inclusion" ] unless Inventory::Movement::ADJUSTMENT_REASONS.include?(@reason)
        fields["note"] = [ "invalid" ] unless @note.nil? || @note.is_a?(String)
        fields["note"] = [ "too_long" ] if @note.is_a?(String) && @note.length > Inventory::Movement::NOTE_MAX_LENGTH
        fields["idempotency_key"] = [ "invalid" ] unless Idempotency.valid_key?(@idempotency_key)

        Result.failure(:validation_failed, fields:) if fields.any?
      end
  end
end

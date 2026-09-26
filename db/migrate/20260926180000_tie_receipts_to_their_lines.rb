class TieReceiptsToTheirLines < ActiveRecord::Migration[8.1]
  # ADR 0017, invariants 2 and 6 at the database. A receipt's lines, the ledger
  # and the payable are append-only behind a revoke and a trigger, but what
  # guards them from being received twice (an order line's received figures),
  # what the payable is worth (the receipt's total) and what entered stock (the
  # movement) were only as good as the command that wrote them. Each is now
  # checked when the transaction commits, so the rows can be written in any
  # order, and refuses a write that does not agree with the append-only rows it
  # summarizes: the received figures are the sum of the receipt lines, a receipt
  # is worth the sum of its lines, a movement is what its line says, and a
  # receipt line is for the product of the order line it consumes.
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION purchasing_order_line_matches_receipts() RETURNS trigger AS $$
        DECLARE
          target_id bigint;
          counted record;
          summed record;
        BEGIN
          IF TG_TABLE_NAME = 'purchasing_order_lines' THEN
            target_id := NEW.id;
          ELSE
            target_id := NEW.order_line_id;
          END IF;

          SELECT product_id, received_quantity, received_stock_quantity, received_gross_cents, received_discount_cents
            INTO counted FROM purchasing_order_lines WHERE id = target_id;
          IF NOT FOUND THEN
            RETURN NULL;
          END IF;

          IF TG_TABLE_NAME = 'purchasing_receipt_lines' AND NEW.product_id <> counted.product_id THEN
            RAISE EXCEPTION 'receipt line % is for product %, but its order line % is for product %',
              NEW.id, NEW.product_id, target_id, counted.product_id;
          END IF;

          SELECT COALESCE(SUM(quantity), 0) AS quantity, COALESCE(SUM(stock_quantity), 0) AS stock_quantity,
                 COALESCE(SUM(gross_cents), 0) AS gross_cents, COALESCE(SUM(discount_cents), 0) AS discount_cents
            INTO summed FROM purchasing_receipt_lines WHERE organization_id = NEW.organization_id AND order_line_id = target_id;

          IF (counted.received_quantity, counted.received_stock_quantity, counted.received_gross_cents, counted.received_discount_cents)
             IS DISTINCT FROM (summed.quantity, summed.stock_quantity, summed.gross_cents, summed.discount_cents) THEN
            RAISE EXCEPTION 'order line % records % received (% in stock units, % gross, % discount) but its receipt lines add up to %, %, %, %',
              target_id, counted.received_quantity, counted.received_stock_quantity, counted.received_gross_cents, counted.received_discount_cents,
              summed.quantity, summed.stock_quantity, summed.gross_cents, summed.discount_cents;
          END IF;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER purchasing_order_lines_match_receipts
          AFTER INSERT OR UPDATE OF received_quantity, received_stock_quantity, received_gross_cents, received_discount_cents
          ON purchasing_order_lines DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION purchasing_order_line_matches_receipts();
        CREATE CONSTRAINT TRIGGER purchasing_receipt_lines_match_order_line
          AFTER INSERT ON purchasing_receipt_lines DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION purchasing_order_line_matches_receipts();

        CREATE FUNCTION purchasing_receipt_matches_lines() RETURNS trigger AS $$
        DECLARE
          target_id bigint;
          expected bigint;
          actual numeric;
        BEGIN
          IF TG_TABLE_NAME = 'purchasing_receipts' THEN
            target_id := NEW.id;
          ELSE
            target_id := NEW.receipt_id;
          END IF;

          SELECT total_cents INTO expected FROM purchasing_receipts WHERE id = target_id;
          IF expected IS NULL THEN
            RETURN NULL;
          END IF;

          SELECT COALESCE(SUM(net_cents), 0) INTO actual FROM purchasing_receipt_lines WHERE receipt_id = target_id;
          IF actual <> expected THEN
            RAISE EXCEPTION 'the lines of receipt % add up to %, not to its total of %', target_id, actual, expected;
          END IF;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER purchasing_receipts_total_matches_lines
          AFTER INSERT ON purchasing_receipts DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION purchasing_receipt_matches_lines();
        CREATE CONSTRAINT TRIGGER purchasing_receipt_lines_total_matches_receipt
          AFTER INSERT ON purchasing_receipt_lines DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION purchasing_receipt_matches_lines();

        CREATE FUNCTION inventory_movement_matches_receipt_line() RETURNS trigger AS $$
        DECLARE
          line record;
        BEGIN
          SELECT stock_quantity, net_cents INTO line FROM purchasing_receipt_lines WHERE id = NEW.receipt_line_id;
          IF NOT FOUND THEN
            RETURN NULL;
          END IF;

          IF (NEW.quantity, NEW.value_cents) IS DISTINCT FROM (line.stock_quantity, line.net_cents) THEN
            RAISE EXCEPTION 'movement % is % worth % but its receipt line % brought in % worth %',
              NEW.id, NEW.quantity, NEW.value_cents, NEW.receipt_line_id, line.stock_quantity, line.net_cents;
          END IF;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER inventory_movements_match_receipt_line
          AFTER INSERT ON inventory_movements DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW WHEN (NEW.receipt_line_id IS NOT NULL)
          EXECUTE FUNCTION inventory_movement_matches_receipt_line();
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER inventory_movements_match_receipt_line ON inventory_movements;
        DROP FUNCTION inventory_movement_matches_receipt_line();
        DROP TRIGGER purchasing_receipt_lines_total_matches_receipt ON purchasing_receipt_lines;
        DROP TRIGGER purchasing_receipts_total_matches_lines ON purchasing_receipts;
        DROP FUNCTION purchasing_receipt_matches_lines();
        DROP TRIGGER purchasing_receipt_lines_match_order_line ON purchasing_receipt_lines;
        DROP TRIGGER purchasing_order_lines_match_receipts ON purchasing_order_lines;
        DROP FUNCTION purchasing_order_line_matches_receipts();
      SQL
    end
  end
end

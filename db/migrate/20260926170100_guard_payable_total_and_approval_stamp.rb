class GuardPayableTotalAndApprovalStamp < ActiveRecord::Migration[8.1]
  # A payable is what its receipt cost: the title's total equals the receipt's, checked
  # when the title is written (the receipt is always written first; a payable with
  # no receipt at all is refused by its own check). And an order
  # that is or was approved carries the stamp of when: receiving reads it, and
  # nothing but the approval command could set a status without one, so the
  # database says it too. The check on the existing table is added NOT VALID and
  # validated in the next migration.
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION finance_payable_matches_receipt() RETURNS trigger AS $$
        DECLARE
          receipt_total bigint;
        BEGIN
          IF NEW.kind = 'payable' AND NEW.receipt_id IS NOT NULL THEN
            SELECT total_cents INTO receipt_total FROM purchasing_receipts WHERE id = NEW.receipt_id;
            IF receipt_total IS DISTINCT FROM NEW.total_cents THEN
              RAISE EXCEPTION 'a payable of % does not match its receipt of %', NEW.total_cents, receipt_total;
            END IF;
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER finance_titles_match_receipt BEFORE INSERT ON finance_titles
          FOR EACH ROW EXECUTE FUNCTION finance_payable_matches_receipt();
      SQL
    end

    add_check_constraint :purchasing_orders, "status IN ('draft', 'cancelled') OR approved_at IS NOT NULL",
      name: "purchasing_orders_approval_stamped", validate: false
  end

  def down
    remove_check_constraint :purchasing_orders, name: "purchasing_orders_approval_stamped"
    safety_assured do
      execute <<~SQL
        DROP TRIGGER finance_titles_match_receipt ON finance_titles;
        DROP FUNCTION finance_payable_matches_receipt();
      SQL
    end
  end
end

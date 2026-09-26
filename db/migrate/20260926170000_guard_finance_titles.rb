class GuardFinanceTitles < ActiveRecord::Migration[8.1]
  # ADR 0017, invariant 5 and the money invariants at the database: a title's
  # installments always add up to its total (checked when the transaction
  # commits, so the title and its installments can be written in either order),
  # what a title and its installments were created with cannot be edited, and the
  # app role cannot delete one: a title is closed by its status.
  def up
    safety_assured do
      execute <<~SQL
        CREATE FUNCTION finance_title_matches_installments() RETURNS trigger AS $$
        DECLARE
          target_id bigint;
          expected bigint;
          actual bigint;
        BEGIN
          IF TG_TABLE_NAME = 'finance_titles' THEN
            target_id := NEW.id;
          ELSIF TG_OP = 'DELETE' THEN
            target_id := OLD.title_id;
          ELSE
            target_id := NEW.title_id;
          END IF;

          SELECT total_cents INTO expected FROM finance_titles WHERE id = target_id;
          IF expected IS NULL THEN
            RETURN NULL;
          END IF;

          SELECT COALESCE(SUM(amount_cents), 0) INTO actual FROM finance_installments WHERE title_id = target_id;
          IF actual <> expected THEN
            RAISE EXCEPTION 'the installments of title % add up to %, not to its total of %', target_id, actual, expected;
          END IF;
          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER finance_titles_total_matches_installments
          AFTER INSERT ON finance_titles DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION finance_title_matches_installments();
        CREATE CONSTRAINT TRIGGER finance_installments_total_matches_title
          AFTER INSERT OR UPDATE OF amount_cents, title_id OR DELETE ON finance_installments DEFERRABLE INITIALLY DEFERRED
          FOR EACH ROW EXECUTE FUNCTION finance_title_matches_installments();

        CREATE FUNCTION finance_titles_freeze() RETURNS trigger AS $$
        BEGIN
          IF (NEW.organization_id, NEW.kind, NEW.partner_id, NEW.receipt_id, NEW.total_cents, NEW.currency)
             IS DISTINCT FROM (OLD.organization_id, OLD.kind, OLD.partner_id, OLD.receipt_id, OLD.total_cents, OLD.currency) THEN
            RAISE EXCEPTION 'a title''s kind, partner, receipt and total cannot be changed';
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER finance_titles_freeze BEFORE UPDATE ON finance_titles
          FOR EACH ROW EXECUTE FUNCTION finance_titles_freeze();

        CREATE FUNCTION finance_installments_freeze() RETURNS trigger AS $$
        BEGIN
          IF (NEW.organization_id, NEW.title_id, NEW.number, NEW.amount_cents)
             IS DISTINCT FROM (OLD.organization_id, OLD.title_id, OLD.number, OLD.amount_cents) THEN
            RAISE EXCEPTION 'an installment''s title, number and amount cannot be changed';
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER finance_installments_freeze BEFORE UPDATE ON finance_installments
          FOR EACH ROW EXECUTE FUNCTION finance_installments_freeze();

        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alicerce_app') THEN
            EXECUTE 'REVOKE DELETE ON finance_titles, finance_installments FROM alicerce_app';
          END IF;
        END $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER finance_installments_freeze ON finance_installments;
        DROP FUNCTION finance_installments_freeze();
        DROP TRIGGER finance_titles_freeze ON finance_titles;
        DROP FUNCTION finance_titles_freeze();
        DROP TRIGGER finance_installments_total_matches_title ON finance_installments;
        DROP TRIGGER finance_titles_total_matches_installments ON finance_titles;
        DROP FUNCTION finance_title_matches_installments();
      SQL
    end
  end
end

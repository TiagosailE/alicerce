class CreatePurchasingOrderLines < ActiveRecord::Migration[8.1]
  # ADR 0017. The product's sku and name, the purchase unit and the factor are
  # copied when the line is saved and frozen at approval. The line's amounts are
  # stored; what has been received is kept on the line, updated only by
  # Purchasing::ReceiveGoods under the order's lock.
  def up
    create_table :purchasing_order_lines do |t|
      t.references :organization, null: false, foreign_key: { to_table: :identity_organizations }
      t.bigint :order_id, null: false
      t.integer :position, null: false
      t.bigint :product_id, null: false
      t.string :product_sku, null: false
      t.string :product_name, null: false
      t.bigint :purchase_unit_id, null: false
      t.string :purchase_unit_code, null: false
      t.string :stock_unit_code, null: false
      t.decimal :factor, precision: 15, scale: 6, null: false
      t.decimal :quantity, precision: 15, scale: 3, null: false
      t.bigint :unit_price_cents, null: false
      t.integer :discount_bp, null: false, default: 0
      t.bigint :gross_cents, null: false
      t.bigint :discount_cents, null: false
      t.bigint :net_cents, null: false
      t.decimal :received_quantity, precision: 15, scale: 3, null: false, default: 0
      t.decimal :received_stock_quantity, precision: 15, scale: 3, null: false, default: 0
      t.bigint :received_gross_cents, null: false, default: 0
      t.bigint :received_discount_cents, null: false, default: 0
      t.timestamps
    end

    add_index :purchasing_order_lines, [ :organization_id, :order_id, :id ], unique: true,
      name: "index_purchasing_order_lines_on_organization_order_and_id"
    add_index :purchasing_order_lines, [ :order_id, :position ], unique: true
    add_index :purchasing_order_lines, [ :organization_id, :product_id ]

    add_foreign_key :purchasing_order_lines, :purchasing_orders,
      column: [ :organization_id, :order_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_order_same_organization", validate: false
    add_foreign_key :purchasing_order_lines, :catalog_products,
      column: [ :organization_id, :product_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_product_same_organization", validate: false
    add_foreign_key :purchasing_order_lines, :catalog_units,
      column: [ :organization_id, :purchase_unit_id ], primary_key: [ :organization_id, :id ],
      name: "fk_purchasing_order_lines_unit_same_organization", validate: false

    add_check_constraint :purchasing_order_lines, "quantity > 0", name: "purchasing_order_lines_quantity_positive"
    add_check_constraint :purchasing_order_lines, "factor > 0", name: "purchasing_order_lines_factor_positive"
    add_check_constraint :purchasing_order_lines, "unit_price_cents >= 0", name: "purchasing_order_lines_price_not_negative"
    add_check_constraint :purchasing_order_lines, "discount_bp BETWEEN 0 AND 10000", name: "purchasing_order_lines_discount_range"
    add_check_constraint :purchasing_order_lines,
      "gross_cents >= 0 AND discount_cents >= 0 AND discount_cents <= gross_cents AND net_cents = gross_cents - discount_cents",
      name: "purchasing_order_lines_amounts_consistent"
    add_check_constraint :purchasing_order_lines, "gross_cents <= 1000000000000000", name: "purchasing_order_lines_gross_cap"
    add_check_constraint :purchasing_order_lines,
      "received_quantity BETWEEN 0 AND quantity AND received_stock_quantity >= 0 " \
      "AND received_gross_cents BETWEEN 0 AND gross_cents AND received_discount_cents BETWEEN 0 AND discount_cents " \
      "AND received_discount_cents <= received_gross_cents",
      name: "purchasing_order_lines_received_within_line"
    # The money formula of ADR 0017, stated in the database: a line whose amounts
    # do not follow from its quantity, price and discount could never be received
    # exactly (the last receipt would fail its own bounds, or leave a cent behind).
    # round() on numeric is half away from zero, half up for the non-negatives here.
    add_check_constraint :purchasing_order_lines, "gross_cents = round(quantity * unit_price_cents)",
      name: "purchasing_order_lines_gross_follows_price"
    add_check_constraint :purchasing_order_lines, "discount_cents = round(gross_cents::numeric * discount_bp / 10000)",
      name: "purchasing_order_lines_discount_follows_bp"
    # What the line comes to in stock units must fit a movement's quantity
    # (numeric(15,3)), and what was received of it never exceeds it, so an order
    # that could never be received cannot exist.
    add_check_constraint :purchasing_order_lines, "round(quantity * factor, 3) < 1000000000000",
      name: "purchasing_order_lines_stock_quantity_fits"
    add_check_constraint :purchasing_order_lines, "received_stock_quantity <= round(quantity * factor, 3)",
      name: "purchasing_order_lines_received_stock_within_line"

    safety_assured do
      execute <<~SQL
        -- What a line says once its order is approved never changes (ADR 0017):
        -- quantity, price, discount, factor, unit, product and amounts are frozen,
        -- and a line is neither added to nor removed from an order that is not a
        -- draft. Only what has been received moves, and only by ReceiveGoods.
        CREATE FUNCTION purchasing_order_lines_freeze() RETURNS trigger AS $$
        DECLARE
          parent_status text;
        BEGIN
          SELECT status INTO parent_status FROM purchasing_orders
            WHERE id = (CASE WHEN TG_OP = 'INSERT' THEN NEW.order_id ELSE OLD.order_id END);

          IF parent_status IS DISTINCT FROM 'draft' THEN
            IF TG_OP <> 'UPDATE' THEN
              RAISE EXCEPTION 'lines of a purchase order that is not a draft cannot be % (order status: %)', lower(TG_OP), parent_status;
            END IF;

            IF (NEW.order_id, NEW.position, NEW.product_id, NEW.purchase_unit_id, NEW.factor, NEW.quantity, NEW.unit_price_cents,
                NEW.discount_bp, NEW.gross_cents, NEW.discount_cents, NEW.net_cents)
               IS DISTINCT FROM
               (OLD.order_id, OLD.position, OLD.product_id, OLD.purchase_unit_id, OLD.factor, OLD.quantity, OLD.unit_price_cents,
                OLD.discount_bp, OLD.gross_cents, OLD.discount_cents, OLD.net_cents) THEN
              RAISE EXCEPTION 'the lines of a purchase order that is not a draft are frozen (order status: %)', parent_status;
            END IF;
          END IF;

          RETURN COALESCE(NEW, OLD);
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER purchasing_order_lines_freeze
          BEFORE INSERT OR UPDATE OR DELETE ON purchasing_order_lines
          FOR EACH ROW EXECUTE FUNCTION purchasing_order_lines_freeze();

        ALTER TABLE purchasing_order_lines ENABLE ROW LEVEL SECURITY;

        CREATE POLICY purchasing_order_lines_tenant_isolation ON purchasing_order_lines
          USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)
          WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint);
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER IF EXISTS purchasing_order_lines_freeze ON purchasing_order_lines;
        DROP FUNCTION IF EXISTS purchasing_order_lines_freeze();
      SQL
    end

    drop_table :purchasing_order_lines
  end
end

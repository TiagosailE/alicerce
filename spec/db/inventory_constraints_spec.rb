require "rails_helper"

RSpec.describe "Inventory constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:actor) { create(:user) }

  # Created up front: a record first built inside an expectation's savepoint
  # loses its id when that savepoint rolls back.
  before do
    set_current_tenant(organization)
    actor
  end

  def product_and_warehouse(org = organization)
    set_current_tenant(org)
    [ create(:product, organization: org), create(:warehouse, organization: org) ]
  end

  def insert_balance(org: organization, product:, warehouse:, on_hand: 0, reserved: 0, allowance: 0, value_cents: 0, cost: 0, currency: "BRL")
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO inventory_balances (organization_id, product_id, warehouse_id, on_hand, reserved, negative_allowance,
                                        value_cents, last_unit_cost, currency, created_at, updated_at)
        VALUES (#{org.id}, #{product.id}, #{warehouse.id}, #{on_hand}, #{reserved}, #{allowance}, #{value_cents}, #{cost},
                '#{currency}', now(), now())
      SQL
    end
  end

  def insert_movement(org: organization, product:, warehouse:, kind: "adjustment", reason: "count", quantity: 5, value_cents: 500, currency: "BRL")
    reason_sql = reason ? "'#{reason}'" : "NULL"
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO inventory_movements (organization_id, product_id, warehouse_id, kind, quantity, value_cents, currency,
                                         on_hand_after, value_after_cents, reason, actor_user_id, created_at)
        VALUES (#{org.id}, #{product.id}, #{warehouse.id}, '#{kind}', #{quantity}, #{value_cents}, '#{currency}',
                #{quantity}, #{value_cents}, #{reason_sql}, #{actor.id}, now())
      SQL
    end
  end

  describe "inventory_balances" do
    let(:pair) { product_and_warehouse }

    it "accepts an ordinary balance" do
      product, warehouse = pair

      expect { insert_balance(product:, warehouse:, on_hand: 10, value_cents: 850) }.not_to raise_error
    end

    it "keeps on_hand from going below zero unless an allowance covers it (invariant 1)" do
      product, warehouse = pair

      expect { insert_balance(product:, warehouse:, on_hand: -1, value_cents: -100) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_on_hand_within_allowance/)
      expect { insert_balance(product:, warehouse:, on_hand: -5, value_cents: -500, allowance: 5) }.not_to raise_error
    end

    it "refuses a negative reserved quantity and a negative allowance" do
      product, warehouse = pair

      expect { insert_balance(product:, warehouse:, reserved: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_reserved_not_negative/)
      expect { insert_balance(product:, warehouse:, allowance: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_allowance_not_negative/)
    end

    it "keeps the value in step with the stock" do
      product, warehouse = pair

      expect { insert_balance(product:, warehouse:, on_hand: 0, value_cents: 5) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_value_follows_stock/)
      expect { insert_balance(product:, warehouse:, on_hand: 5, value_cents: -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_value_follows_stock/)
    end

    it "accepts only BRL" do
      product, warehouse = pair

      expect { insert_balance(product:, warehouse:, currency: "USD") }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_balances_currency_brl/)
    end

    it "holds one row per product and warehouse" do
      product, warehouse = pair
      insert_balance(product:, warehouse:)

      expect { insert_balance(product:, warehouse:) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_inventory_balances_on_organization_product_and_warehouse/)
    end

    it "refuses a product or a warehouse of another organization, at the composite foreign key" do
      product, warehouse = pair
      foreign_product, foreign_warehouse = product_and_warehouse(other_organization)
      set_current_tenant(organization)

      expect { insert_balance(product: foreign_product, warehouse:) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_inventory_balances_product_same_organization/)
      expect { insert_balance(product:, warehouse: foreign_warehouse) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_inventory_balances_warehouse_same_organization/)
    end

    it "hides another organization's balance and refuses to insert one for it (row level security)" do
      product, warehouse = pair
      insert_balance(product:, warehouse:, on_hand: 1, value_cents: 1)
      id = connection.select_value("SELECT id FROM inventory_balances LIMIT 1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM inventory_balances WHERE id = #{id}").to_i).to eq(0)
      expect { insert_balance(org: organization, product:, warehouse:) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  describe "inventory_movements" do
    let(:pair) { product_and_warehouse }

    it "accepts an ordinary adjustment" do
      product, warehouse = pair

      expect { insert_movement(product:, warehouse:) }.not_to raise_error
    end

    it "requires a reason for an adjustment, and a known one" do
      product, warehouse = pair

      expect { insert_movement(product:, warehouse:, reason: nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_adjustment_has_reason/)
      expect { insert_movement(product:, warehouse:, reason: "whim") }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_reason_valid/)
    end

    it "refuses an adjustment that moves nothing, and an unknown kind" do
      product, warehouse = pair

      expect { insert_movement(product:, warehouse:, quantity: 0, value_cents: 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_adjustment_moves_stock/)
      expect { insert_movement(product:, warehouse:, kind: "teleport") }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_kind_valid/)
    end

    it "keeps the value in the direction of the quantity" do
      product, warehouse = pair

      expect { insert_movement(product:, warehouse:, quantity: -5, value_cents: 500) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_value_follows_quantity/)
      expect { insert_movement(product:, warehouse:, quantity: 5, value_cents: -500) }
        .to raise_error(ActiveRecord::StatementInvalid, /inventory_movements_value_follows_quantity/)
    end

    it "refuses a product or a warehouse of another organization, at the composite foreign key" do
      product, warehouse = pair
      foreign_product, foreign_warehouse = product_and_warehouse(other_organization)
      set_current_tenant(organization)

      expect { insert_movement(product: foreign_product, warehouse:) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_inventory_movements_product_same_organization/)
      expect { insert_movement(product:, warehouse: foreign_warehouse) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_inventory_movements_warehouse_same_organization/)
    end

    it "is append-only: the app role can neither update nor delete a movement (ADR 0016)" do
      product, warehouse = pair
      insert_movement(product:, warehouse:)

      expect { connection.transaction(requires_new: true) { connection.execute("UPDATE inventory_movements SET quantity = 99") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied|append-only/)
      expect { connection.transaction(requires_new: true) { connection.execute("DELETE FROM inventory_movements") } }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied|append-only/)
    end

    it "is read-only at the model too" do
      product, warehouse = pair
      movement = Inventory::Movement.create!(
        organization:, product:, warehouse:, kind: "adjustment", reason: "count", quantity: 1, value_cents: 1,
        on_hand_after: 1, value_after_cents: 1, actor_user: actor
      )

      expect { movement.update!(note: "edited") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { movement.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "hides another organization's movement and refuses to insert one for it (row level security)" do
      product, warehouse = pair
      insert_movement(product:, warehouse:)
      id = connection.select_value("SELECT id FROM inventory_movements LIMIT 1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM inventory_movements WHERE id = #{id}").to_i).to eq(0)
      expect { insert_movement(org: organization, product:, warehouse:) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  describe "idempotency_keys" do
    def insert_key(org: organization, key: "key-#{SecureRandom.hex(6)}")
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO idempotency_keys (organization_id, user_id, key, request_digest, created_at)
          VALUES (#{org.id}, #{actor.id}, '#{key}', 'digest', now())
        SQL
      end
    end

    it "is unique per organization, user and key" do
      insert_key(key: "same-key-1")

      expect { insert_key(key: "same-key-1") }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_idempotency_keys_on_organization_user_and_key/)
    end

    it "hides another organization's keys and refuses to insert one for it (row level security)" do
      insert_key(key: "hidden-key-1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM idempotency_keys").to_i).to eq(0)
      expect { insert_key(org: organization, key: "intruder-1") }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end
end

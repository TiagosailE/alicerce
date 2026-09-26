require "rails_helper"

RSpec.describe "Purchasing constraints" do
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

  # An order that is or was approved carries the stamp of its approval; stamped: false
  # leaves it out, to see what the database says about that.
  def insert_order(org: organization, supplier:, number: 1, status: "draft", installments: 1, total_cents: 0, stamped: true)
    approved_at = stamped && %w[draft cancelled].exclude?(status) ? "now()" : "NULL"
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO purchasing_orders (organization_id, number, supplier_id, supplier_name, supplier_document_type, supplier_document_number,
                                       status, installments, total_cents, approved_at, created_by_user_id, created_at, updated_at)
        VALUES (#{org.id}, #{number}, #{supplier.id}, 'Fornecedor', 'cnpj', 'x', '#{status}', #{installments}, #{total_cents}, #{approved_at}, #{actor.id}, now(), now())
      SQL
    end
  end

  def insert_line(org: organization, order_id:, product:, unit:, position: 1, quantity: 10, price: 100, bp: 0, gross: 1000, discount: 0, net: 1000,
                  received: 0, received_gross: 0, received_discount: 0)
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO purchasing_order_lines (organization_id, order_id, position, product_id, product_sku, product_name, purchase_unit_id,
                                            purchase_unit_code, stock_unit_code, factor, quantity, unit_price_cents, discount_bp, gross_cents,
                                            discount_cents, net_cents, received_quantity, received_gross_cents, received_discount_cents,
                                            created_at, updated_at)
        VALUES (#{org.id}, #{order_id}, #{position}, #{product.id}, 'SKU', 'Produto', #{unit.id}, 'SC', 'UN', 1, #{quantity}, #{price}, #{bp}, #{gross},
                #{discount}, #{net}, #{received}, #{received_gross}, #{received_discount}, now(), now())
      SQL
    end
  end

  let(:supplier) { supplier_for(organization) }
  let(:product) { orderable_product(organization, sku: "CIM-001") }
  let(:unit) { product.unit_conversion.purchase_unit }

  describe "purchasing_orders" do
    it "accepts an ordinary draft" do
      expect { insert_order(supplier:) }.not_to raise_error
    end

    it "numbers each organization's orders once" do
      insert_order(supplier:, number: 5)

      expect { insert_order(supplier:, number: 5) }.to raise_error(ActiveRecord::RecordNotUnique, /index_purchasing_orders_on_organization_id_and_number/)
    end

    it "refuses a supplier of another organization, at the composite foreign key" do
      set_current_tenant(other_organization)
      foreign = supplier_for(other_organization)
      set_current_tenant(organization)

      expect { insert_order(supplier: foreign) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_orders_supplier_same_organization/)
    end

    it "knows only the five states, installments from 1 to 24 and a total inside the cap" do
      expect { insert_order(supplier:, status: "shipped", number: 2) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_orders_status_valid/)
      expect { insert_order(supplier:, installments: 25, number: 3) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_orders_installments_range/)
      expect { insert_order(supplier:, total_cents: 10**15 + 1, number: 4) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_orders_total_range/)
    end

    it "carries the stamp of its approval once it is approved, partly or wholly received (nothing else can read the day it was approved)" do
      %w[approved partially_received received].each_with_index do |status, index|
        expect { insert_order(supplier:, status:, number: 20 + index, stamped: false) }
          .to raise_error(ActiveRecord::StatementInvalid, /purchasing_orders_approval_stamped/)
      end
      expect { insert_order(supplier:, status: "cancelled", number: 30) }.not_to raise_error
    end

    it "hides another organization's order and refuses to insert one for it (row level security)" do
      insert_order(supplier:)
      id = connection.select_value("SELECT id FROM purchasing_orders LIMIT 1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM purchasing_orders WHERE id = #{id}").to_i).to eq(0)
      expect { insert_order(org: organization, supplier:, number: 9) }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end

  describe "purchasing_order_lines" do
    let(:order_id) do
      insert_order(supplier:)
      connection.select_value("SELECT id FROM purchasing_orders LIMIT 1")
    end

    it "accepts an ordinary line, and one position per order" do
      expect { insert_line(order_id:, product:, unit:) }.not_to raise_error
      expect { insert_line(order_id:, product:, unit:) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a product or a unit of another organization, at the composite foreign keys" do
      set_current_tenant(other_organization)
      foreign_product = orderable_product(other_organization, sku: "ALHEIO-1")
      foreign_unit = foreign_product.unit_conversion.purchase_unit
      set_current_tenant(organization)
      id = order_id

      expect { insert_line(order_id: id, product: foreign_product, unit:) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_order_lines_product_same_organization/)
      expect { insert_line(order_id: id, product:, unit: foreign_unit) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_purchasing_order_lines_unit_same_organization/)
    end

    it "keeps the amounts consistent: net is gross minus discount, and a discount never exceeds the gross" do
      expect { insert_line(order_id:, product:, unit:, gross: 1000, discount: 100, net: 950) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_amounts_consistent/)
      expect { insert_line(order_id:, product:, unit:, gross: 1000, discount: 1100, net: -100) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_amounts_consistent/)
    end

    it "keeps a discount inside 0 to 10000 basis points and a quantity positive" do
      expect { insert_line(order_id:, product:, unit:, bp: 10_001, discount: 1000, net: 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_discount_range/)
      expect { insert_line(order_id:, product:, unit:, quantity: 0, gross: 0, net: 0) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_quantity_positive/)
    end

    it "never lets what was received exceed what was ordered, in quantity, gross or discount" do
      expect { insert_line(order_id:, product:, unit:, received: 11) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
      expect { insert_line(order_id:, product:, unit:, received_gross: 1001) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
      expect { insert_line(order_id:, product:, unit:, bp: 1000, discount: 100, net: 900, received_discount: 101) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
      expect { insert_line(order_id:, product:, unit:, bp: 1000, discount: 100, net: 900, received_gross: 50, received_discount: 60) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
    end

    it "hides another organization's line and refuses to insert one for it (row level security)" do
      insert_line(order_id:, product:, unit:)
      id = connection.select_value("SELECT id FROM purchasing_order_lines LIMIT 1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM purchasing_order_lines WHERE id = #{id}").to_i).to eq(0)
      # The freeze trigger looks the parent order up under the same row level
      # security, so it refuses first; either way another organization cannot write.
      expect { insert_line(org: organization, order_id:, product:, unit:, position: 2) }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security|cannot be insert/)
    end

    it "refuses a line whose order belongs to another organization, at the composite foreign key" do
      set_current_tenant(other_organization)
      foreign_supplier = supplier_for(other_organization)
      insert_order(org: other_organization, supplier: foreign_supplier)
      foreign_order_id = connection.select_value("SELECT id FROM purchasing_orders LIMIT 1")
      set_current_tenant(organization)

      expect { insert_line(org: organization, order_id: foreign_order_id, product:, unit:) }
        .to raise_error(ActiveRecord::StatementInvalid, /fk_purchasing_order_lines_order_same_organization|cannot be insert/)
    end

    describe "the money formula, in the database (ADR 0017)" do
      it "refuses a gross that is not quantity x price rounded half up" do
        # 3 x 3225 = 9675; 9674 and 9676 are both wrong
        expect { insert_line(order_id:, product:, unit:, quantity: 3, price: 3225, gross: 9674, net: 9674) }
          .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_gross_follows_price/)
        expect { insert_line(order_id:, product:, unit:, quantity: 3, price: 3225, gross: 9675, net: 9675) }.not_to raise_error
      end

      it "refuses a discount that is not the gross's share in basis points rounded half up" do
        # 3225 at 2% is 64.5: 65 half up, not 64
        expect { insert_line(order_id:, product:, unit:, quantity: 1, price: 3225, bp: 200, gross: 3225, discount: 64, net: 3161) }
          .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_discount_follows_bp/)
        expect { insert_line(order_id:, product:, unit:, quantity: 1, price: 3225, bp: 200, gross: 3225, discount: 65, net: 3160) }.not_to raise_error
      end

      it "refuses a line that could never be received because it does not fit a stock movement" do
        # 999999999999.999 x factor 2 is past the numeric(15,3) a movement holds
        expect do
          connection.transaction(requires_new: true) do
            connection.execute(<<~SQL)
              INSERT INTO purchasing_order_lines (organization_id, order_id, position, product_id, product_sku, product_name, purchase_unit_id,
                purchase_unit_code, stock_unit_code, factor, quantity, unit_price_cents, discount_bp, gross_cents, discount_cents, net_cents,
                created_at, updated_at)
              VALUES (#{organization.id}, #{order_id}, 1, #{product.id}, 'SKU', 'P', #{unit.id}, 'SC', 'UN', 2, 999999999999.999, 0, 0, 0, 0, 0, now(), now())
            SQL
          end
        end.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_stock_quantity_fits/)
      end
    end

    describe "freezing (the lines of an order that is not a draft)" do
      def order_status!(id, status)
        connection.execute("UPDATE purchasing_orders SET status = '#{status}', approved_at = now() WHERE id = #{id}")
      end

      let(:line_id) do
        insert_line(order_id:, product:, unit:)
        connection.select_value("SELECT id FROM purchasing_order_lines LIMIT 1")
      end

      it "lets a draft's lines change, be added and be removed" do
        id = line_id

        expect { connection.execute("UPDATE purchasing_order_lines SET quantity = 20, gross_cents = 2000, net_cents = 2000 WHERE id = #{id}") }.not_to raise_error
        expect { insert_line(order_id:, product:, unit:, position: 2) }.not_to raise_error
        expect { connection.execute("DELETE FROM purchasing_order_lines WHERE position = 2") }.not_to raise_error
      end

      it "refuses to change what a line says once the order is approved" do
        id = line_id
        order_status!(order_id, "approved")

        {
          "quantity = 11, gross_cents = 1100, net_cents = 1100" => "quantity",
          "unit_price_cents = 101, gross_cents = 1010, net_cents = 1010" => "price",
          "discount_bp = 100, discount_cents = 10, net_cents = 990" => "discount",
          "factor = 2" => "factor",
          "position = 9" => "position"
        }.each_key do |assignment|
          expect { connection.transaction(requires_new: true) { connection.execute("UPDATE purchasing_order_lines SET #{assignment} WHERE id = #{id}") } }
            .to raise_error(ActiveRecord::StatementInvalid, /are frozen/), "expected #{assignment} to be refused"
        end
      end

      it "still lets what has been received move, and refuses to add or remove a line" do
        id = line_id
        order_status!(order_id, "approved")

        expect do
          connection.execute("UPDATE purchasing_order_lines SET received_quantity = 4, received_stock_quantity = 4, received_gross_cents = 400 WHERE id = #{id}")
        end.not_to raise_error
        expect { insert_line(order_id:, product:, unit:, position: 2) }.to raise_error(ActiveRecord::StatementInvalid, /cannot be insert/)
        expect { connection.transaction(requires_new: true) { connection.execute("DELETE FROM purchasing_order_lines WHERE id = #{id}") } }
          .to raise_error(ActiveRecord::StatementInvalid, /cannot be delete/)
      end
    end
  end
end

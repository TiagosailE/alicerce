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

  def insert_order(org: organization, supplier:, number: 1, status: "draft", installments: 1, total_cents: 0)
    connection.transaction(requires_new: true) do
      connection.execute(<<~SQL)
        INSERT INTO purchasing_orders (organization_id, number, supplier_id, supplier_name, supplier_document_type, supplier_document_number,
                                       status, installments, total_cents, created_by_user_id, created_at, updated_at)
        VALUES (#{org.id}, #{number}, #{supplier.id}, 'Fornecedor', 'cnpj', 'x', '#{status}', #{installments}, #{total_cents}, #{actor.id}, now(), now())
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
      expect { insert_line(order_id:, product:, unit:, bp: 10_001) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_discount_range/)
      expect { insert_line(order_id:, product:, unit:, quantity: 0) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_quantity_positive/)
    end

    it "never lets what was received exceed what was ordered, in quantity, gross or discount" do
      expect { insert_line(order_id:, product:, unit:, received: 11) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
      expect { insert_line(order_id:, product:, unit:, received_gross: 1001) }.to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
      expect { insert_line(order_id:, product:, unit:, discount: 100, net: 900, received_discount: 101) }
        .to raise_error(ActiveRecord::StatementInvalid, /purchasing_order_lines_received_within_line/)
    end

    it "hides another organization's line and refuses to insert one for it (row level security)" do
      insert_line(order_id:, product:, unit:)
      id = connection.select_value("SELECT id FROM purchasing_order_lines LIMIT 1")

      set_current_tenant(other_organization)
      expect(connection.select_value("SELECT count(*) FROM purchasing_order_lines WHERE id = #{id}").to_i).to eq(0)
      expect { insert_line(org: organization, order_id:, product:, unit:, position: 2) }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end
  end
end

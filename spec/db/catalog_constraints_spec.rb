require "rails_helper"

RSpec.describe "Catalog constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  it "hides another organization's unit from a plain query" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)

    set_current_tenant(other_organization)
    expect(connection.select_value("SELECT count(*) FROM catalog_units WHERE id = #{unit.id}").to_i).to eq(0)
  end

  it "refuses to insert a unit for another organization" do
    set_current_tenant(other_organization)

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_units (organization_id, code, name, created_at, updated_at)
          VALUES (#{organization.id}, 'XX', 'Invasor', now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end

  # A raw INSERT that violates a constraint aborts the current Postgres
  # transaction; wrapping it in its own requires_new: true sub-transaction
  # (a real SAVEPOINT) keeps that abort from poisoning the spec's own
  # transactional fixture, same as the RLS example above.
  it "rejects a duplicate category name that differs only by case, at the index itself" do
    set_current_tenant(organization)
    create(:category, organization:, name: "Ferragens")

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_categories (organization_id, name, created_at, updated_at)
          VALUES (#{organization.id}, 'FERRAGENS', now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_categories_on_organization_id_and_lower_name/)
  end

  it "rejects a duplicate product sku that differs only by case, at the index itself" do
    set_current_tenant(organization)
    unit = create(:unit, organization:)
    create(:product, organization:, sku: "TIJ-001", stock_unit: unit)

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_products (organization_id, sku, name, stock_unit_id, created_at, updated_at)
          VALUES (#{organization.id}, 'tij-001', 'Outro tijolo', #{unit.id}, now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_products_on_organization_id_and_lower_sku/)
  end

  it "rejects a unit conversion with a non-positive factor, at the check constraint itself" do
    set_current_tenant(organization)
    product = create(:product, organization:)
    unit = product.stock_unit

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_unit_conversions (organization_id, product_id, purchase_unit_id, factor, created_at, updated_at)
          VALUES (#{organization.id}, #{product.id}, #{unit.id}, 0, now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /catalog_unit_conversions_factor_positive/)
  end

  it "rejects a second unit conversion for the same product, at the index itself" do
    set_current_tenant(organization)
    product = create(:product, organization:)
    create(:unit_conversion, organization:, product:)
    another_unit = create(:unit, organization:)

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_unit_conversions (organization_id, product_id, purchase_unit_id, factor, created_at, updated_at)
          VALUES (#{organization.id}, #{product.id}, #{another_unit.id}, 2, now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  # Row level security does not apply to foreign key checks, so a plain
  # single-column foreign key would accept an id that exists but belongs to
  # another organization. The composite (organization_id, x_id) keys are the
  # only thing that turns that into an error for a write that bypasses the
  # models (insert_all, a data-fix script).
  describe "composite foreign keys" do
    let(:foreign_unit) do
      set_current_tenant(other_organization)
      create(:unit, organization: other_organization).tap { set_current_tenant(organization) }
    end

    it "rejects a product whose stock unit belongs to another organization" do
      unit_id = foreign_unit.id

      expect {
        connection.transaction(requires_new: true) do
          connection.execute(<<~SQL)
            INSERT INTO catalog_products (organization_id, sku, name, stock_unit_id, created_at, updated_at)
            VALUES (#{organization.id}, 'INV-001', 'Produto invasor', #{unit_id}, now(), now())
          SQL
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_catalog_products_stock_unit_same_organization/)
    end

    it "rejects a product whose category belongs to another organization" do
      set_current_tenant(other_organization)
      category = create(:category, organization: other_organization)
      set_current_tenant(organization)
      unit = create(:unit, organization:)

      expect {
        connection.transaction(requires_new: true) do
          connection.execute(<<~SQL)
            INSERT INTO catalog_products (organization_id, sku, name, category_id, stock_unit_id, created_at, updated_at)
            VALUES (#{organization.id}, 'INV-002', 'Produto invasor', #{category.id}, #{unit.id}, now(), now())
          SQL
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_catalog_products_category_same_organization/)
    end

    it "rejects a unit conversion whose purchase unit belongs to another organization" do
      unit_id = foreign_unit.id
      product = create(:product, organization:)

      expect {
        connection.transaction(requires_new: true) do
          connection.execute(<<~SQL)
            INSERT INTO catalog_unit_conversions (organization_id, product_id, purchase_unit_id, factor, created_at, updated_at)
            VALUES (#{organization.id}, #{product.id}, #{unit_id}, 2, now(), now())
          SQL
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_catalog_unit_conversions_purchase_unit_same_organization/)
    end

    it "rejects a unit conversion whose product belongs to another organization" do
      set_current_tenant(other_organization)
      foreign_product = create(:product, organization: other_organization)
      set_current_tenant(organization)
      unit = create(:unit, organization:)

      expect {
        connection.transaction(requires_new: true) do
          connection.execute(<<~SQL)
            INSERT INTO catalog_unit_conversions (organization_id, product_id, purchase_unit_id, factor, created_at, updated_at)
            VALUES (#{organization.id}, #{foreign_product.id}, #{unit.id}, 2, now(), now())
          SQL
        end
      }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_catalog_unit_conversions_product_same_organization/)
    end

    it "still accepts a product that uses the organization's own unit" do
      set_current_tenant(organization)
      unit = create(:unit, organization:)

      expect {
        connection.execute(<<~SQL)
          INSERT INTO catalog_products (organization_id, sku, name, stock_unit_id, created_at, updated_at)
          VALUES (#{organization.id}, 'OK-001', 'Produto legitimo', #{unit.id}, now(), now())
        SQL
      }.not_to raise_error
    end
  end

  # document_number is encrypted (ADR 0012): TenantScoped's default_scope is
  # not the only thing standing between organizations here, so this table
  # gets the same raw-SQL proof every other catalog table already has,
  # rather than trusting the ActiveRecord-level tests alone.
  it "hides another organization's partner from a plain query" do
    set_current_tenant(organization)
    partner = create(:partner, organization:)

    set_current_tenant(other_organization)
    expect(connection.select_value("SELECT count(*) FROM catalog_partners WHERE id = #{partner.id}").to_i).to eq(0)
  end

  it "refuses to insert a partner for another organization" do
    set_current_tenant(other_organization)

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_partners (organization_id, name, document_type, document_number, customer, created_at, updated_at)
          VALUES (#{organization.id}, 'Invasor', 'cpf', '#{DocumentNumberGenerator.cpf}', true, now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end

  it "rejects a duplicate document_number within the same organization, at the index itself" do
    set_current_tenant(organization)
    partner = create(:partner, organization:)
    ciphertext = connection.select_value("SELECT document_number FROM catalog_partners WHERE id = #{partner.id}")

    expect {
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_partners (organization_id, name, document_type, document_number, customer, created_at, updated_at)
          VALUES (#{organization.id}, 'Outro nome', 'cpf', #{connection.quote(ciphertext)}, true, now(), now())
        SQL
      end
    }.to raise_error(ActiveRecord::RecordNotUnique, /index_catalog_partners_on_organization_id_and_document_number/)
  end

  describe "partner check constraints" do
    def insert_partner(document_type:, customer:, supplier:)
      connection.transaction(requires_new: true) do
        connection.execute(<<~SQL)
          INSERT INTO catalog_partners (organization_id, name, document_type, document_number, customer, supplier, created_at, updated_at)
          VALUES (#{organization.id}, 'Parceiro', '#{document_type}', 'cipher-#{SecureRandom.hex(4)}', #{customer}, #{supplier}, now(), now())
        SQL
      end
    end

    before { set_current_tenant(organization) }

    it "rejects a document type other than cpf or cnpj" do
      expect { insert_partner(document_type: "rg", customer: true, supplier: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_partners_document_type_valid/)
    end

    it "rejects a partner that is neither customer nor supplier" do
      expect { insert_partner(document_type: "cpf", customer: false, supplier: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /catalog_partners_customer_or_supplier/)
    end

    it "accepts a supplier only" do
      expect { insert_partner(document_type: "cnpj", customer: false, supplier: true) }.not_to raise_error
    end
  end

  # Every request spec goes through TenantScoped's default scope, so none of
  # them would notice a dropped or weakened policy: these prove Postgres
  # itself refuses the other organization, table by table.
  describe "row level security on the remaining master data tables" do
    def cross_organization_insert(sql)
      set_current_tenant(other_organization)
      expect { connection.transaction(requires_new: true) { connection.execute(sql) } }
        .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
    end

    def visible_to_other_organization?(table, id)
      set_current_tenant(other_organization)
      connection.select_value("SELECT count(*) FROM #{table} WHERE id = #{id}").to_i.positive?
    end

    it "isolates catalog_categories" do
      set_current_tenant(organization)
      category = create(:category, organization:)

      expect(visible_to_other_organization?("catalog_categories", category.id)).to be(false)
      cross_organization_insert(<<~SQL)
        INSERT INTO catalog_categories (organization_id, name, created_at, updated_at)
        VALUES (#{organization.id}, 'Invasora', now(), now())
      SQL
    end

    it "isolates catalog_products" do
      set_current_tenant(organization)
      product = create(:product, organization:)

      expect(visible_to_other_organization?("catalog_products", product.id)).to be(false)
      cross_organization_insert(<<~SQL)
        INSERT INTO catalog_products (organization_id, sku, name, stock_unit_id, created_at, updated_at)
        VALUES (#{organization.id}, 'INV-900', 'Invasor', #{product.stock_unit_id}, now(), now())
      SQL
    end

    it "isolates catalog_unit_conversions" do
      set_current_tenant(organization)
      product = create(:product, organization:)
      conversion = create(:unit_conversion, organization:, product:)
      spare_product = create(:product, organization:)

      expect(visible_to_other_organization?("catalog_unit_conversions", conversion.id)).to be(false)
      cross_organization_insert(<<~SQL)
        INSERT INTO catalog_unit_conversions (organization_id, product_id, purchase_unit_id, factor, created_at, updated_at)
        VALUES (#{organization.id}, #{spare_product.id}, #{spare_product.stock_unit_id}, 2, now(), now())
      SQL
    end

    it "isolates inventory_warehouses" do
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:)

      expect(visible_to_other_organization?("inventory_warehouses", warehouse.id)).to be(false)
      cross_organization_insert(<<~SQL)
        INSERT INTO inventory_warehouses (organization_id, name, created_at, updated_at)
        VALUES (#{organization.id}, 'Invasor', now(), now())
      SQL
    end
  end
end

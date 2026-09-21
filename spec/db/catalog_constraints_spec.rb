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
end

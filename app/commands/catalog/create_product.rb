module Catalog
  # Creates a product and its purchase unit conversion together (ADR 0006:
  # "purchase units convert to the stock unit with a per-product factor"),
  # so a product never exists without one. If neither is exiting, the
  # caller has already asked for stock_unit and purchase_unit to be the
  # same and factor 1.
  #
  # Error codes: :validation_failed (product or conversion fields).
  class CreateProduct
    def self.call(...) = new(...).call

    def initialize(organization:, sku:, name:, stock_unit_id:, purchase_unit_id:, factor:, actor:, category_id: nil)
      @organization = organization
      @sku = sku
      @name = name
      @category_id = category_id
      @stock_unit_id = stock_unit_id
      @purchase_unit_id = purchase_unit_id
      @factor = factor
      @actor = actor
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        product = Catalog::Product.new(
          organization: @organization, sku: @sku, name: @name,
          category_id: @category_id, stock_unit_id: @stock_unit_id
        )
        unless product.save
          result = Result.invalid(product)
          raise ActiveRecord::Rollback
        end

        conversion = Catalog::UnitConversion.new(
          organization: @organization, product:, purchase_unit_id: @purchase_unit_id, factor: @factor
        )
        unless conversion.save
          result = Result.invalid(conversion)
          raise ActiveRecord::Rollback
        end

        Audit.record("product_created", product, actor: @actor, changes: { sku: product.sku, name: product.name })
        result = Result.success(product)
      end

      result
    end
  end
end

module Catalog
  class Product < ApplicationRecord
    include TenantScoped
    include RaceSafeUniqueness

    belongs_to :category, class_name: "Catalog::Category", optional: true
    belongs_to :stock_unit, class_name: "Catalog::Unit"
    has_one :unit_conversion, class_name: "Catalog::UnitConversion", dependent: :destroy, inverse_of: :product

    validates :sku, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
    validates :name, presence: true
    validate :category_belongs_to_the_same_organization
    validate :stock_unit_never_changes, on: :update

    private
      # Every quantity of a product is stored in its stock unit, so changing
      # it would silently reinterpret them (500 UN becoming 500 MIL). Until
      # slice 3 defines stock movements there is nothing to check a change
      # against, so it is never allowed; slice 3 relaxes this to "while the
      # product has no movement" (ADR 0015).
      def stock_unit_never_changes
        errors.add(:stock_unit, :immutable) if stock_unit_id_changed?
      end

      # category is optional (unlike stock_unit, a required belongs_to that
      # already gets this for free): Rails only force-loads an association
      # to validate it when presence is required, so a category_id for
      # another organization, or one that does not exist at all, would
      # otherwise reach the database unnoticed. TenantScoped's default scope
      # means the association resolves to nil in both cases, same as any
      # other tenant-scoped lookup; the foreign key alone cannot catch this
      # since Postgres row level security does not apply to FK checks.
      def category_belongs_to_the_same_organization
        errors.add(:category, :not_found) if category_id.present? && category.nil?
      end
  end
end

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

    private
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

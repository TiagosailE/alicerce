module Catalog
  class Category < ApplicationRecord
    include TenantScoped
    include RaceSafeUniqueness

    has_many :products, dependent: :restrict_with_error

    validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
  end
end

module Catalog
  # A unit of measure (unidade, saco, milheiro, metro cúbico...). code is the
  # short form shown in tables; name is the full description.
  class Unit < ApplicationRecord
    include TenantScoped

    validates :code, presence: true, uniqueness: { scope: :organization_id }
    validates :name, presence: true
  end
end

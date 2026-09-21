module Inventory
  class Warehouse < ApplicationRecord
    include TenantScoped

    validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
  end
end

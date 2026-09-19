module Identity
  class Membership < ApplicationRecord
    ROLES = %w[owner admin purchasing sales finance read_only].freeze

    belongs_to :organization
    belongs_to :user

    validates :role, inclusion: { in: ROLES }
    validates :user_id, uniqueness: { scope: :organization_id }
  end
end

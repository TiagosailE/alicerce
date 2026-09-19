module Identity
  class Organization < ApplicationRecord
    has_many :memberships, dependent: :restrict_with_exception
    has_many :users, through: :memberships

    validates :name, presence: true
    validate :time_zone_exists

    private
      def time_zone_exists
        TZInfo::Timezone.get(time_zone.to_s)
      rescue TZInfo::InvalidTimezoneIdentifier
        errors.add(:time_zone, :inclusion)
      end
  end
end

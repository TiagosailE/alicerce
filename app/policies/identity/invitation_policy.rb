module Identity
  class InvitationPolicy < ApplicationPolicy
    def create?
      Identity::Capabilities.manage_members?(user, membership)
    end

    private
      def membership
        user&.membership_in(Current.organization)
      end
  end
end

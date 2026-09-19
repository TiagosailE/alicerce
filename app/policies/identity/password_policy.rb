module Identity
  class PasswordPolicy < ApplicationPolicy
    def update?
      Identity::Capabilities.change_own_password?(user)
    end
  end
end

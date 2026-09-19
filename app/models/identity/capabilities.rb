module Identity
  # Maps roles to capabilities (ADR 0008), so the matrix lives in one file
  # instead of scattered across policies. Add a capability here only when a
  # real policy needs it; do not build ahead of a caller.
  module Capabilities
    module_function

    def view_audit_trail?(membership)
      return false unless membership

      %w[owner admin].include?(membership.role)
    end

    # ADR 0008: denied to demo users regardless of role, so the public demo
    # can be explored freely without anyone inviting people, sending email
    # or changing authentication settings on the shared account.
    def manage_members?(user, membership)
      return false unless membership
      return false if user&.demo?

      %w[owner admin].include?(membership.role)
    end

    # ADR 0008: denied to demo users, so the public demo's shared account
    # cannot be locked out by a visitor changing its password. Any role
    # may change their own password otherwise.
    def change_own_password?(user)
      user.present? && !user.demo?
    end
  end
end

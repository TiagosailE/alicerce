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
  end
end

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

    # ADR 0008 matrix, "Master data (partners, products, warehouses)":
    # owner, admin and purchasing manage it; not demo-gated, unlike
    # manage_members?, since demo visitors must see the full loop.
    def manage_master_data?(membership)
      return false unless membership

      %w[owner admin purchasing].include?(membership.role)
    end

    # Every role can at least read master data (ADR 0008: sales, finance
    # and read_only get "read").
    def view_master_data?(membership)
      membership.present?
    end

    # ADR 0016: every role can read balances and the movement ledger (sales
    # needs available stock, finance the value); adjusting is owner, admin and
    # purchasing (ADR 0008's matrix), and read_only reads.
    def view_stock?(membership)
      membership.present?
    end

    # What stock is worth and what it cost is margin information: every role
    # but sales sees it (finance and the owners run the books, read_only
    # observes them, ADR 0008), so a salesperson cannot read the cost of the
    # products they sell off a stock list.
    def view_stock_value?(membership)
      membership.present? && membership.role != "sales"
    end

    # The ledger shows who moved what, why and, in the note, whatever the
    # operator typed, so it is not for sales (ADR 0008's matrix gives sales no
    # stock access beyond seeing what is available to sell): sales reads the
    # balances, quantities only.
    def view_stock_movements?(membership)
      membership.present? && membership.role != "sales"
    end

    def adjust_stock?(membership)
      return false unless membership

      %w[owner admin purchasing].include?(membership.role)
    end

    # ADR 0008's matrix: owner, admin and purchasing write purchase orders and
    # receipts, finance and read_only read them, sales has no access at all.
    def view_purchasing?(membership)
      membership.present? && membership.role != "sales"
    end

    def manage_purchasing?(membership)
      return false unless membership

      %w[owner admin purchasing].include?(membership.role)
    end

    # ADR 0017: payables are titles, which the people who run the books read:
    # owner, admin, finance and read_only. Purchasing creates the receipt that
    # opens one but does not read what the organization owes; sales has no access.
    def view_payables?(membership)
      membership.present? && %w[owner admin finance read_only].include?(membership.role)
    end

    # ADR 0014: the full CPF, e-mail and phone of a partner are personal
    # data, so read_only sees them masked or absent; every role that works
    # with customers and suppliers sees them.
    def view_partner_personal_data?(membership)
      return false unless membership

      membership.role != "read_only"
    end
  end
end

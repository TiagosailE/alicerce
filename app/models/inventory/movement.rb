module Inventory
  # A row of the immutable ledger (ADR 0016): a signed quantity and value, and
  # the balance right after it. The database stops UPDATE and DELETE (the app
  # role has neither privilege and a trigger stops everyone but the owner);
  # readonly? here is the same rule one layer earlier. A mistake is corrected
  # by a new movement, never by an edit.
  class Movement < ApplicationRecord
    include TenantScoped

    ADJUSTMENT_REASONS = %w[opening_balance count loss damage theft expiry found other].freeze
    # A reason states why stock moved, so it has a direction: a theft is never
    # an increase and a found item is never a decrease. Reports built on
    # reasons (losses, the income statement) rely on this. count and other
    # go either way.
    DECREASE_ONLY_REASONS = %w[loss damage theft expiry].freeze
    INCREASE_ONLY_REASONS = %w[opening_balance found].freeze
    NOTE_MAX_LENGTH = 500

    belongs_to :product, class_name: "Catalog::Product"
    belongs_to :warehouse, class_name: "Inventory::Warehouse"
    belongs_to :actor_user, class_name: "Identity::User"
    # Set on a receipt movement only (a database check states both directions).
    belongs_to :receipt_line, class_name: "Purchasing::ReceiptLine", optional: true

    def readonly? = persisted? || super
  end
end

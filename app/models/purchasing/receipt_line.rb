module Purchasing
  # One order line's share of a receipt (ADR 0017), with what it was priced with
  # copied, so the receipt stands on its own. Immutable like its receipt.
  class ReceiptLine < ApplicationRecord
    include TenantScoped

    belongs_to :receipt, class_name: "Purchasing::Receipt", inverse_of: :lines
    belongs_to :order_line, class_name: "Purchasing::OrderLine"
    belongs_to :product, class_name: "Catalog::Product"
    has_one :movement, class_name: "Inventory::Movement"

    def readonly? = persisted? || super
  end
end

module Purchasing
  # Goods received against an approved order (ADR 0017): a posted, immutable
  # document, like the ledger movements it writes. The database refuses UPDATE
  # and DELETE for the app role and by trigger for everyone but the owner;
  # readonly? here is the same rule one layer earlier. A mistake is not edited:
  # it is corrected by a new record (a stock adjustment, the payable cancelled),
  # since Milestone 1 has no reversal.
  class Receipt < ApplicationRecord
    include TenantScoped

    # A receipt holds its whole write phase under the receipt counter's lock, at
    # about a dozen statements a line, so an order with more open lines than this
    # is received in more than one receipt.
    MAX_LINES = 50
    SUPPLIER_INVOICE_MAX_LENGTH = 60
    SUPPLIER_INVOICE_FORMAT = %r{\A[[:alnum:]][[:alnum:] ./-]*\z}
    # An invoice number is a few digits plus a series; the 44 digits of an NF-e
    # access key are not one.
    SUPPLIER_INVOICE_MAX_DIGITS = 15

    belongs_to :order, class_name: "Purchasing::Order"
    belongs_to :warehouse, class_name: "Inventory::Warehouse"
    belongs_to :created_by_user, class_name: "Identity::User"
    has_many :lines, -> { order(:id) }, class_name: "Purchasing::ReceiptLine", inverse_of: :receipt
    has_one :title, class_name: "Finance::Title"

    def readonly? = persisted? || super
  end
end

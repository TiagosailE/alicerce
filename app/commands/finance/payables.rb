module Finance
  # Opens the payable a receipt creates (ADR 0017): one title for the receipt's
  # total, in the order's installments, every installment at least one cent. No
  # title is opened for a receipt worth nothing. Called inside the receiving
  # command's transaction, after its locks.
  module Payables
    module_function

    # The number of installments is what the order asked for, but never more
    # than the cents to split, so none is zero. Money.allocate gives the first
    # parts the extra cent. Due dates are day offsets from the receipt date,
    # with no month-end drift and no business-day adjustment.
    def open_for(receipt:, order:, total_cents:)
      return unless total_cents.positive?

      title = Finance::Title.create!(
        organization_id: receipt.organization_id, kind: "payable", partner_id: order.supplier_id, partner_name: order.supplier_name,
        receipt:, total_cents:
      )
      amounts = Money.allocate(total_cents, [ order.installments, total_cents ].min)
      amounts.each_with_index do |amount, index|
        Finance::Installment.create!(
          organization_id: receipt.organization_id, title:, number: index + 1, amount_cents: amount,
          due_on: receipt.received_on + order.first_due_days + (index * order.interval_days)
        )
      end
      title
    end
  end
end

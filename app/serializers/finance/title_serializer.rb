module Finance
  # A title with its installments. What has been settled and what is still open
  # come from the stored figures: no screen sums them.
  class TitleSerializer
    def initialize(title)
      @title = title
    end

    def as_json
      installments = @title.installments.to_a
      settled = installments.sum(&:settled_cents)
      {
        id: @title.id,
        kind: @title.kind,
        status: @title.status,
        partner: { id: @title.partner_id, name: @title.partner_name },
        receipt: @title.receipt && { id: @title.receipt_id, number: @title.receipt.number },
        total_cents: @title.total_cents,
        settled_cents: settled,
        open_cents: @title.total_cents - settled,
        currency: @title.currency,
        created_at: @title.created_at.utc.iso8601,
        installments: installments.map { |installment| installment_json(installment) }
      }
    end

    private
      def installment_json(installment)
        {
          id: installment.id,
          number: installment.number,
          due_on: installment.due_on.iso8601,
          amount_cents: installment.amount_cents,
          settled_cents: installment.settled_cents,
          open_cents: installment.open_cents
        }
      end
  end
end

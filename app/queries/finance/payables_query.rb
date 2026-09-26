module Finance
  # Payables (the titles of kind payable), newest first, with their installments.
  # q matches the supplier's name as copied onto the title.
  class PayablesQuery
    include Pagination

    def results
      paginated(@scope.includes(:installments, :receipt).order(id: :desc))
    end

    private
      def filtered(scope, status: nil, q: nil)
        scope = scope.where(kind: "payable")
        scope = scope.where(status:) if status.present?
        scope = scope.where("finance_titles.partner_name ILIKE ?", "%#{sanitize_like(q)}%") if q.present?
        scope
      end
  end
end

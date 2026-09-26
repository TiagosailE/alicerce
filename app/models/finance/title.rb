module Finance
  # What an organization owes or is owed for one document (ADR 0017): a payable
  # for one receipt now, a receivable for one invoice with slice 5. Its total is
  # the sum of its installments, which are always at least one cent each. The
  # partner's name is copied when the title is created, so a corrected partner
  # never rewrites it (ADR 0015).
  class Title < ApplicationRecord
    include TenantScoped
    include HasStateMachine

    KINDS = %w[payable receivable].freeze
    # Slice 6 adds the paid states. A cancelled title is final; nothing deletes one.
    TRANSITIONS = { "open" => %w[cancelled], "cancelled" => [] }.freeze
    STATUSES = TRANSITIONS.keys.freeze

    belongs_to :partner, class_name: "Catalog::Partner"
    belongs_to :receipt, class_name: "Purchasing::Receipt", optional: true
    has_many :installments, -> { order(:number) }, class_name: "Finance::Installment", inverse_of: :title
  end
end

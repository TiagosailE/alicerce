module Purchasing
  # A purchase order (ADR 0017). Its status moves only through the transition
  # table below (ADR 0009), by a command that has locked the row and re-read it.
  # The supplier's name and document are copied when the order is created, so a
  # corrected partner never rewrites an old order (ADR 0015); the document number
  # is stored encrypted (ADR 0012), without a lookup, so non-deterministically.
  class Order < ApplicationRecord
    include TenantScoped
    include HasStateMachine

    TRANSITIONS = {
      "draft" => %w[approved cancelled],
      "approved" => %w[partially_received received cancelled],
      "partially_received" => %w[partially_received received cancelled],
      "received" => [],
      "cancelled" => []
    }.freeze
    STATUSES = TRANSITIONS.keys.freeze
    NOTE_MAX_LENGTH = 1000
    MAX_LINES = 200

    encrypts :supplier_document_number

    belongs_to :supplier, class_name: "Catalog::Partner"
    belongs_to :created_by_user, class_name: "Identity::User"
    belongs_to :approved_by_user, class_name: "Identity::User", optional: true
    belongs_to :cancelled_by_user, class_name: "Identity::User", optional: true
    # The commands validate the lines themselves (BuildLines reports each one by
    # field), so the order does not validate them a second time.
    has_many :lines, -> { order(:position) }, class_name: "Purchasing::OrderLine", inverse_of: :order,
      dependent: :destroy, validate: false

    validates :installments, numericality: { only_integer: true, in: 1..24 }
    validates :first_due_days, :interval_days, numericality: { only_integer: true, in: 0..365 }
    validates :note, length: { maximum: NOTE_MAX_LENGTH }

    def draft? = status == "draft"
  end
end

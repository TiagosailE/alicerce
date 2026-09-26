module Finance
  # One due date and amount of a title, and how much of it has been settled.
  class Installment < ApplicationRecord
    include TenantScoped

    belongs_to :title, class_name: "Finance::Title", inverse_of: :installments

    def open_cents = amount_cents - settled_cents
  end
end

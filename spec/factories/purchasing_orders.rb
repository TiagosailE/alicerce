FactoryBot.define do
  factory :purchase_order, class: "Purchasing::Order" do
    organization
    supplier { association :partner, organization:, customer: false, supplier: true }
    created_by_user { association :user }
    sequence(:number) { |n| n }
    supplier_name { supplier.name }
    supplier_document_type { supplier.document_type }
    supplier_document_number { supplier.document_number }
    status { "draft" }
    approved_at { Time.current unless %w[draft cancelled].include?(status) }
  end
end

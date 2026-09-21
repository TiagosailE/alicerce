FactoryBot.define do
  factory :warehouse, class: "Inventory::Warehouse" do
    organization
    sequence(:name) { |n| "Depósito #{n}" }
  end
end

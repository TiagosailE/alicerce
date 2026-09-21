FactoryBot.define do
  factory :unit, class: "Catalog::Unit" do
    organization
    sequence(:code) { |n| "UN#{n}" }
    sequence(:name) { |n| "Unidade #{n}" }
  end

  factory :category, class: "Catalog::Category" do
    organization
    sequence(:name) { |n| "Categoria #{n}" }
  end

  # stock_unit defaults to a unit in the same organization as the product,
  # not a factory-created unit of its own, or a product could end up
  # pointing at another organization's unit whenever a spec overrides
  # organization: without also overriding stock_unit:.
  factory :product, class: "Catalog::Product" do
    organization
    sequence(:sku) { |n| "SKU#{n}" }
    sequence(:name) { |n| "Produto #{n}" }
    stock_unit { association :unit, organization: organization }
  end

  factory :unit_conversion, class: "Catalog::UnitConversion" do
    organization
    product { association :product, organization: organization }
    purchase_unit { association :unit, organization: organization }
    factor { "1.0" }
  end

  # document_number is a generated, check-digit-valid CPF by default
  # (docs/scope.md: seeds and specs never use a real document); a trait
  # switches to a generated CNPJ for specs that need a supplier.
  factory :partner, class: "Catalog::Partner" do
    organization
    sequence(:name) { |n| "Cliente #{n}" }
    document_type { "cpf" }
    document_number { DocumentNumberGenerator.cpf }
    customer { true }

    trait :supplier do
      document_type { "cnpj" }
      document_number { DocumentNumberGenerator.cnpj }
      customer { false }
      supplier { true }
    end
  end
end

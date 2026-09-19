FactoryBot.define do
  factory :organization, class: "Identity::Organization" do
    sequence(:name) { |n| "Distribuidora Teste #{n}" }
  end

  factory :user, class: "Identity::User" do
    sequence(:email) { |n| "pessoa#{n}@alicerce.example" }
    name { "Pessoa de Teste" }
    password { "senha-de-teste-longa" }
  end

  factory :membership, class: "Identity::Membership" do
    organization
    user
    role { "owner" }
  end
end

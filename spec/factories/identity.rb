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

  factory :invitation, class: "Identity::Invitation" do
    organization
    invited_by factory: :user
    sequence(:email) { |n| "convidado#{n}@alicerce.example" }
    role { "sales" }
    token_digest { Identity::Invitation.digest(SecureRandom.urlsafe_base64(32)) }
    expires_at { Identity::Invitation::EXPIRY.from_now }
  end
end

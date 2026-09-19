# Idempotent: safe to run in every environment. Outside development, the demo
# password must be provided, so a fresh production database can never seed
# with a guessable default (ADR 0002, docs/security.md).
password = ENV.fetch("SEED_USER_PASSWORD") { "alicerce-demo-2026" if Rails.env.development? }
raise "Set SEED_USER_PASSWORD to seed outside development" if password.blank?

canion = Identity::Organization.find_or_create_by!(name: "Cânion Materiais de Construção") do |org|
  org.time_zone = "America/Bahia"
  org.demo = true
end

serra = Identity::Organization.find_or_create_by!(name: "Ferragens Serra Dourada") do |org|
  org.time_zone = "America/Sao_Paulo"
  org.demo = true
end

def seed_member(organization, email:, name:, role:, password:)
  user = Identity::User.find_or_create_by!(email:) do |u|
    u.name = name
    u.password = password
    u.demo = true
  end
  Identity::Membership.find_or_create_by!(organization:, user:) { |m| m.role = role }
  user
end

seed_member(canion, email: "joana.lima@canion.example", name: "Joana Lima", role: "owner", password:)
seed_member(canion, email: "rafael.souza@canion.example", name: "Rafael Souza", role: "sales", password:)
seed_member(canion, email: "marcia.alves@canion.example", name: "Márcia Alves", role: "finance", password:)

seed_member(serra, email: "pedro.rocha@serradourada.example", name: "Pedro Rocha", role: "owner", password:)

puts "Seeded #{Identity::Organization.count} organizations and #{Identity::User.count} users."

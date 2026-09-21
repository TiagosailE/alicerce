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

# Catalog (slice 2): TenantScoped models need Current.organization set before
# any query, including find_or_create_by!'s own lookup.
def seed_unit(organization, code:, name:)
  Catalog::Unit.find_or_create_by!(organization:, code:) { |unit| unit.name = name }
end

def seed_category(organization, name:)
  Catalog::Category.find_or_create_by!(organization:, name:)
end

def seed_product(organization, sku:, name:, stock_unit:, purchase_unit:, factor:, category: nil)
  product = Catalog::Product.find_or_create_by!(organization:, sku:) do |p|
    p.name = name
    p.stock_unit = stock_unit
    p.category = category
  end
  Catalog::UnitConversion.find_or_create_by!(organization:, product:) do |conversion|
    conversion.purchase_unit = purchase_unit
    conversion.factor = factor
  end
  product
end

Current.organization = canion
unidade = seed_unit(canion, code: "UN", name: "Unidade")
saco = seed_unit(canion, code: "SC", name: "Saco")
milheiro = seed_unit(canion, code: "MIL", name: "Milheiro")
barra = seed_unit(canion, code: "BR", name: "Barra")
seed_unit(canion, code: "M3", name: "Metro cúbico")

cimento_categoria = seed_category(canion, name: "Cimento e argamassa")
ferragens_categoria = seed_category(canion, name: "Ferragens")
alvenaria_categoria = seed_category(canion, name: "Alvenaria e agregados")

seed_product(canion, sku: "CIM-001", name: "Cimento CP II-32 (saco 50kg)",
  stock_unit: unidade, purchase_unit: saco, factor: 1, category: cimento_categoria)
seed_product(canion, sku: "VER-001", name: "Vergalhão CA-50 8mm (barra 12m)",
  stock_unit: unidade, purchase_unit: barra, factor: 1, category: ferragens_categoria)
seed_product(canion, sku: "TIJ-001", name: "Tijolo comum 8 furos",
  stock_unit: unidade, purchase_unit: milheiro, factor: 1000, category: alvenaria_categoria)
Current.organization = nil

Current.organization = serra
serra_unidade = seed_unit(serra, code: "UN", name: "Unidade")
serra_caixa = seed_unit(serra, code: "CX", name: "Caixa")
serra_categoria = seed_category(serra, name: "Ferragens")
seed_product(serra, sku: "DOB-001", name: "Dobradiça 3\" cromada",
  stock_unit: serra_unidade, purchase_unit: serra_caixa, factor: 12, category: serra_categoria)
Current.organization = nil

puts "Seeded #{Identity::Organization.count} organizations and #{Identity::User.count} users."

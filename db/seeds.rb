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
seed_member(canion, email: "bruno.tavares@canion.example", name: "Bruno Tavares", role: "purchasing", password:)

seed_member(serra, email: "pedro.rocha@serradourada.example", name: "Pedro Rocha", role: "owner", password:)

# Master data (slice 2): TenantScoped models need Current.organization set
# before any query, including find_or_create_by!'s own lookup. Warehouses
# live under Inventory:: (glossary), not Catalog::, even though they are
# seeded here alongside it.
def seed_unit(organization, code:, name:)
  Catalog::Unit.find_or_create_by!(organization:, code:) { |unit| unit.name = name }
end

def seed_category(organization, name:)
  Catalog::Category.find_or_create_by!(organization:, name:)
end

def seed_warehouse(organization, name:)
  Inventory::Warehouse.find_or_create_by!(organization:, name:)
end

# document_number is generated and fictitious (docs/scope.md: never a real
# CPF or CNPJ in seeds), but still check-digit valid, produced the same way
# a spec would (DocumentNumberGenerator, lib/).
def seed_partner(organization, name:, document_type:, document_number:, customer: false, supplier: false, email: nil, phone: nil)
  Catalog::Partner.find_or_create_by!(organization:, document_number:) do |partner|
    partner.name = name
    partner.document_type = document_type
    partner.customer = customer
    partner.supplier = supplier
    partner.email = email
    partner.phone = phone
  end
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

# Opening stock (slice 3) goes through the real command, so the balances, the
# ledger and the average cost come out exactly as they would in use. The key is
# derived from the ids, so running the seeds again replays instead of adding
# stock a second time. unit_cost is in cents per stock unit (ADR 0016).
def seed_stock(organization, actor:, product:, warehouse:, quantity:, unit_cost:)
  # The idempotency key alone would not keep this safe to rerun: keys expire
  # after 24 hours (ADR 0005), and a second run against a balance that has moved
  # would be refused as stale. A balance with any history is left alone.
  return if Inventory::Movement.exists?(product_id: product.id, warehouse_id: warehouse.id)

  result = Inventory::AdjustStock.call(
    organization:, actor:, product:, warehouse:, counted_quantity: quantity, expected_on_hand: "0", reason: "opening_balance",
    unit_cost_cents: unit_cost, idempotency_key: "seed-#{organization.id}-#{product.id}-#{warehouse.id}",
    request_digest: "seed-opening-balance"
  )
  raise "Seeding stock failed: #{result.error} #{result.details}" unless result.success?
end

# Purchase orders (slice 4) go through the real commands too, so the amounts, the
# numbers, the stock and the payables come out as they would in use. An order is
# found again by its note, so running the seeds twice never adds a second one.
def seed_order(organization, actor:, supplier:, note:, lines:, installments:, approve: true)
  existing = Purchasing::Order.find_by(note:)
  return existing if existing

  created = Purchasing::CreateOrder.call(organization:, actor:, supplier:, lines:, note:, installments:)
  raise "Seeding an order failed: #{created.error} #{created.details}" unless created.success?

  order = created.value
  return order unless approve

  approved = Purchasing::ApproveOrder.call(order:, actor:, revision: order.revision)
  raise "Approving a seeded order failed: #{approved.error} #{approved.details}" unless approved.success?

  order.reload
end

def seed_receipt(organization, actor:, order:, warehouse:, invoice:)
  return if Purchasing::Receipt.exists?(order_id: order.id)

  lines = order.lines.map { |line| { order_line_id: line.id, quantity: DecimalString.format(line.quantity, 3) } }
  result = Purchasing::ReceiveGoods.call(
    organization:, actor:, order:, warehouse:, lines:, supplier_invoice_number: invoice,
    received_on: Time.current.in_time_zone(organization.time_zone).to_date.to_s,
    idempotency_key: "seed-receipt-#{organization.id}-#{order.id}", request_digest: "seed-receipt"
  )
  raise "Seeding a receipt failed: #{result.error} #{result.details}" unless result.success?
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

cimento = seed_product(canion, sku: "CIM-001", name: "Cimento CP II-32 (saco 50kg)",
  stock_unit: unidade, purchase_unit: saco, factor: 1, category: cimento_categoria)
vergalhao = seed_product(canion, sku: "VER-001", name: "Vergalhão CA-50 8mm (barra 12m)",
  stock_unit: unidade, purchase_unit: barra, factor: 1, category: ferragens_categoria)
tijolo = seed_product(canion, sku: "TIJ-001", name: "Tijolo comum 8 furos",
  stock_unit: unidade, purchase_unit: milheiro, factor: 1000, category: alvenaria_categoria)

loja = seed_warehouse(canion, name: "Loja")
patio = seed_warehouse(canion, name: "Pátio")

# A brick costs 84.99 cents (R$ 849,90 the thousand): the fractional cost is why
# the unit cost is a decimal string and the value is rounded once, half up.
joana = Identity::User.find_by!(email: "joana.lima@canion.example")
seed_stock(canion, actor: joana, product: cimento, warehouse: loja, quantity: "120", unit_cost: "3250")
seed_stock(canion, actor: joana, product: cimento, warehouse: patio, quantity: "300", unit_cost: "3180")
seed_stock(canion, actor: joana, product: vergalhao, warehouse: loja, quantity: "80", unit_cost: "5490")
seed_stock(canion, actor: joana, product: vergalhao, warehouse: patio, quantity: "150", unit_cost: "5390")
seed_stock(canion, actor: joana, product: tijolo, warehouse: patio, quantity: "12000", unit_cost: "84.99")
seed_stock(canion, actor: joana, product: tijolo, warehouse: loja, quantity: "2500", unit_cost: "84.99")

# Fictitious, check-digit-valid documents (docs/scope.md), generated once
# with DocumentNumberGenerator and hardcoded so db:seed stays idempotent;
# the alphanumeric CNPJ (ADR 0012) shows up here, the numeric one below for
# Ferragens Serra Dourada, so both coexisting formats appear in the demo.
seed_partner(canion, name: "Cimentos Bahia Distribuidora Ltda", document_type: "cnpj", document_number: "NXKE3INSKJRI36",
  supplier: true, email: "vendas@cimentosbahia.example", phone: "+55 71 3333-1000")
seed_partner(canion, name: "Marcos Pereira", document_type: "cpf", document_number: "32993565770",
  customer: true, email: "marcos.pereira@example.com", phone: "+55 71 99999-2000")

# One order waiting to be received (the demo's receiving flow), one already
# received in full with its payable, and one draft. All three are for the same
# supplier, at prices in cents per purchase unit: a brick is bought by the thousand.
bruno = Identity::User.find_by!(email: "bruno.tavares@canion.example")
cimentos_bahia = Catalog::Partner.find_by!(name: "Cimentos Bahia Distribuidora Ltda")
seed_order(canion, actor: bruno, supplier: cimentos_bahia, note: "Reposição de cimento e vergalhão", installments: 3,
  lines: [
    { product_id: cimento.id, quantity: "200", unit_price_cents: 3_250, discount_bp: 200 },
    { product_id: vergalhao.id, quantity: "100", unit_price_cents: 5_400, discount_bp: 0 }
  ])
tijolo_order = seed_order(canion, actor: bruno, supplier: cimentos_bahia, note: "Tijolo para o pátio", installments: 2,
  lines: [ { product_id: tijolo.id, quantity: "5", unit_price_cents: 84_990, discount_bp: 0 } ])
seed_receipt(canion, actor: bruno, order: tijolo_order, warehouse: patio, invoice: "NF 4821")
seed_order(canion, actor: bruno, supplier: cimentos_bahia, note: "Rascunho de vergalhão", installments: 1, approve: false,
  lines: [ { product_id: vergalhao.id, quantity: "40", unit_price_cents: 5_450, discount_bp: 0 } ])
Current.organization = nil

Current.organization = serra
serra_unidade = seed_unit(serra, code: "UN", name: "Unidade")
serra_caixa = seed_unit(serra, code: "CX", name: "Caixa")
serra_categoria = seed_category(serra, name: "Ferragens")
dobradica = seed_product(serra, sku: "DOB-001", name: "Dobradiça 3\" cromada",
  stock_unit: serra_unidade, purchase_unit: serra_caixa, factor: 12, category: serra_categoria)
deposito = seed_warehouse(serra, name: "Depósito")
seed_stock(serra, actor: Identity::User.find_by!(email: "pedro.rocha@serradourada.example"), product: dobradica,
  warehouse: deposito, quantity: "480", unit_cost: "1290")

seed_partner(serra, name: "Metalúrgica Dourada Ltda", document_type: "cnpj", document_number: "38129140898710",
  supplier: true, email: "vendas@metalurgicadourada.example", phone: "+55 11 3333-4000")
seed_partner(serra, name: "Ana Beatriz Ferreira", document_type: "cpf", document_number: "24098784076",
  customer: true, email: "ana.ferreira@example.com", phone: "+55 11 99999-5000")
Current.organization = nil

puts "Seeded #{Identity::Organization.count} organizations and #{Identity::User.count} users."

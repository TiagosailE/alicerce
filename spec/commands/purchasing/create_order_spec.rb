require "rails_helper"

RSpec.describe Purchasing::CreateOrder do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let(:supplier) { supplier_for(organization, name: "Cimentos Bahia") }
  let(:cimento) { orderable_product(organization, sku: "CIM-001", name: "Cimento CP II") }
  let(:tijolo) { orderable_product(organization, sku: "TIJ-001", name: "Tijolo", purchase_unit_code: "MIL", factor: "1000") }

  before { set_current_tenant(organization) }

  def create_order(lines:, supplier: self.supplier, **options)
    described_class.call(organization:, actor:, supplier:, lines:, **options)
  end

  it "creates a numbered draft with the amounts worked out and stored" do
    result = create_order(lines: [ line_input(cimento, quantity: "200", unit_price_cents: 3_250, discount_bp: 200), line_input(tijolo, quantity: "5", unit_price_cents: 84_990) ],
      installments: 3, first_due_days: 30, interval_days: 30, note: "Entrega na segunda")

    expect(result).to be_success
    order = result.value
    expect(order).to have_attributes(number: 1, status: "draft", revision: 0, installments: 3, total_cents: 637_000 + 424_950, currency: "BRL", note: "Entrega na segunda")
    expect(order.lines.map(&:net_cents)).to eq([ 637_000, 424_950 ])
    expect(order.lines.first).to have_attributes(position: 1, product_sku: "CIM-001", product_name: "Cimento CP II", purchase_unit_code: "SC", factor: BigDecimal("1"))
    expect(order.lines.second).to have_attributes(position: 2, purchase_unit_code: "MIL", stock_unit_code: "UN", factor: BigDecimal("1000"))
  end

  it "copies the supplier's name and document, so a corrected partner never rewrites the order" do
    order = create_order(lines: [ line_input(cimento) ]).value

    supplier.update!(name: "Outro nome")

    expect(order.reload).to have_attributes(supplier_name: "Cimentos Bahia", supplier_document_type: supplier.document_type, supplier_document_number: supplier.document_number)
  end

  it "numbers orders in sequence per organization and gives a number back on failure" do
    expect(create_order(lines: [ line_input(cimento) ]).value.number).to eq(1)
    expect(create_order(lines: [ line_input(cimento, quantity: "abc") ])).not_to be_success
    expect(create_order(lines: [ line_input(cimento) ]).value.number).to eq(2)
  end

  it "records an audit event without personal data" do
    order = create_order(lines: [ line_input(cimento) ]).value

    event = Audit::Event.find_by!(action: "purchase_order_created")
    expect(event.subject_id).to eq(order.id)
    expect(event.field_changes).to eq("number" => 1, "supplier_id" => supplier.id, "total_cents" => 10_000, "lines" => 1)
  end

  describe "validation, all at once and by field" do
    it "names each bad line field" do
      result = create_order(lines: [ { product_id: 0, quantity: "1.2345", unit_price_cents: -5, discount_bp: 10_001 }, line_input(cimento) ])

      expect(result.error).to eq(:validation_failed)
      expect(result.details[:fields]).to eq(
        "lines.0.product_id" => [ "not_found" ], "lines.0.quantity" => [ "too_many_decimals" ],
        "lines.0.unit_price_cents" => [ "out_of_range" ], "lines.0.discount_bp" => [ "out_of_range" ]
      )
      expect(Purchasing::Order.count).to eq(0)
    end

    it "refuses no lines, too many lines and a total past the cap" do
      expect(create_order(lines: []).details[:fields]).to eq("lines" => [ "blank" ])
      expect(create_order(lines: nil).details[:fields]).to eq("lines" => [ "blank" ])
      expect(create_order(lines: Array.new(201) { line_input(cimento) }).details[:fields]).to eq("lines" => [ "too_many" ])
      huge = line_input(cimento, quantity: "400000", unit_price_cents: 10**9)
      expect(create_order(lines: [ huge, huge, huge ]).details[:fields]).to eq("lines" => [ "total_too_large" ])
    end

    it "refuses a product with no purchase conversion, and a floating point price" do
      bare = create(:product, organization:, sku: "SEM-001")

      expect(create_order(lines: [ line_input(bare) ]).details[:fields]).to eq("lines.0.product_id" => [ "conversion_missing" ])
      expect(create_order(lines: [ line_input(cimento, unit_price_cents: 10.5) ]).details[:fields]).to eq("lines.0.unit_price_cents" => [ "not_a_number" ])
    end

    it "refuses a partner that is not an active supplier" do
      customer = create(:partner, organization:, customer: true, supplier: false)
      inactive = supplier_for(organization).tap { |s| s.update!(active: false) }

      expect(create_order(supplier: customer, lines: [ line_input(cimento) ]).details[:fields]).to eq("supplier_id" => [ "not_a_supplier" ])
      expect(create_order(supplier: inactive, lines: [ line_input(cimento) ]).details[:fields]).to eq("supplier_id" => [ "inactive" ])
    end

    it "refuses terms out of range" do
      expect(create_order(lines: [ line_input(cimento) ], installments: 25).details[:fields]).to have_key("installments")
    end

    it "does not reach another organization's product" do
      other = create(:organization)
      set_current_tenant(other)
      foreign = orderable_product(other, sku: "ALHEIO-1")
      set_current_tenant(organization)

      expect(create_order(lines: [ line_input(foreign) ]).details[:fields]).to eq("lines.0.product_id" => [ "not_found" ])
    end
  end
end

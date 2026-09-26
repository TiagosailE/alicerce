require "rails_helper"

RSpec.describe "filter_parameters" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "redacts the partner search term, which is often a person's name" do
    expect(filter.filter("q" => "Marcos Pereira")).to eq("q" => "[FILTERED]")
  end

  it "does not redact parameters that merely contain the letter q" do
    params = { "request_id" => "abc", "quantity" => "3", "sequence" => "9" }

    expect(filter.filter(params)).to eq(params)
  end

  it "redacts the free text typed from a supplier's paper invoice and the notes" do
    filtered = filter.filter("supplier_invoice_number" => "NF 1234 Joao", "note" => "entregar ao Sr. Pedro")

    expect(filtered.values).to all(eq("[FILTERED]"))
  end

  it "redacts the personal data fields" do
    filtered = filter.filter("document_number" => "52998224725", "phone" => "71999990000", "name" => "Ana")

    expect(filtered.values).to all(eq("[FILTERED]"))
  end
end

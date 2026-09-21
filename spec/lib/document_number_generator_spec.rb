require "rails_helper"

RSpec.describe DocumentNumberGenerator do
  it "generates a check-digit-valid CPF every time" do
    50.times { expect(Catalog::DocumentNumber.valid_cpf?(described_class.cpf)).to be(true) }
  end

  it "generates a check-digit-valid alphanumeric CNPJ by default" do
    50.times do
      cnpj = described_class.cnpj
      expect(Catalog::DocumentNumber.valid_cnpj?(cnpj)).to be(true)
      expect(cnpj[0, 12]).to match(/[A-Z]/) # alphanumeric: virtually never all-digit in 50 draws
    end
  end

  it "generates a check-digit-valid numeric CNPJ when asked" do
    50.times do
      cnpj = described_class.cnpj(alphanumeric: false)
      expect(Catalog::DocumentNumber.valid_cnpj?(cnpj)).to be(true)
      expect(cnpj).to match(/\A\d{14}\z/)
    end
  end
end

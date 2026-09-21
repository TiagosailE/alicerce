require "rails_helper"

RSpec.describe Catalog::DocumentNumber do
  describe ".valid_cpf?" do
    it "accepts a real check-digit-valid CPF, regardless of formatting" do
      cpf = DocumentNumberGenerator.cpf
      formatted = cpf.sub(/\A(\d{3})(\d{3})(\d{3})(\d{2})\z/, '\1.\2.\3-\4')

      expect(described_class.valid_cpf?(cpf)).to be(true)
      expect(described_class.valid_cpf?(formatted)).to be(true)
    end

    it "rejects a wrong check digit" do
      cpf = DocumentNumberGenerator.cpf
      tampered = cpf[0, 10] + (cpf[10].to_i == 0 ? "1" : "0")

      expect(described_class.valid_cpf?(tampered)).to be(false)
    end

    it "rejects every digit repeated, even though the checksum alone would pass" do
      expect(described_class.valid_cpf?("11111111111")).to be(false)
    end

    it "rejects the wrong length" do
      expect(described_class.valid_cpf?("123456789")).to be(false)
    end
  end

  describe ".valid_cnpj?" do
    # Receita Federal's own published worked example (Instrucao Normativa
    # RFB 2.229/2024 FAQ, question 14): base 12ABC34501DE checks out to 35.
    it "matches Receita Federal's published alphanumeric worked example" do
      expect(described_class.valid_cnpj?("12.ABC.345/01DE-35")).to be(true)
      expect(described_class.valid_cnpj?("12.ABC.345/01DE-34")).to be(false)
    end

    it "still accepts the legacy all-numeric format" do
      expect(described_class.valid_cnpj?("11.222.333/0001-81")).to be(true)
    end

    it "accepts a generated alphanumeric CNPJ, regardless of formatting" do
      cnpj = DocumentNumberGenerator.cnpj
      formatted = cnpj.sub(/\A(.{2})(.{3})(.{3})(.{4})(\d{2})\z/, '\1.\2.\3/\4-\5')

      expect(described_class.valid_cnpj?(cnpj)).to be(true)
      expect(described_class.valid_cnpj?(formatted)).to be(true)
    end

    it "rejects a wrong check digit" do
      cnpj = DocumentNumberGenerator.cnpj
      tampered = cnpj[0, 13] + (cnpj[13].to_i == 0 ? "1" : "0")

      expect(described_class.valid_cnpj?(tampered)).to be(false)
    end

    it "rejects letters in the check digit positions" do
      expect(described_class.valid_cnpj?("12ABC34501DEAB")).to be(false)
    end

    it "rejects every digit repeated" do
      expect(described_class.valid_cnpj?("00000000000000")).to be(false)
    end

    it "rejects the wrong length" do
      expect(described_class.valid_cnpj?("12345")).to be(false)
    end
  end

  describe ".valid?" do
    it "dispatches on the given type" do
      expect(described_class.valid?("cpf", DocumentNumberGenerator.cpf)).to be(true)
      expect(described_class.valid?("cnpj", DocumentNumberGenerator.cnpj)).to be(true)
      expect(described_class.valid?("other", "12345")).to be(false)
    end
  end

  describe ".normalize" do
    it "strips punctuation and upcases letters" do
      expect(described_class.normalize("12.abc.345/01de-35")).to eq("12ABC34501DE35")
    end
  end
end

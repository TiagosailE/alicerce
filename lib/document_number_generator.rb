# Fictitious, check-digit-valid CPF and CNPJ numbers for seeds and specs
# (docs/scope.md: every document in seeds, tests and screenshots must be
# generated, never a real one). Reuses Catalog::DocumentNumber's own
# checksum so a generated number always passes its own validator.
module DocumentNumberGenerator
  module_function

  ALPHANUMERIC_CHARS = (("0".."9").to_a + ("A".."Z").to_a).freeze

  def cpf
    base = Array.new(9) { rand(10) }
    (base + check_digits(base, Catalog::DocumentNumber::CPF_FIRST_WEIGHTS, Catalog::DocumentNumber::CPF_SECOND_WEIGHTS)).join
  end

  # Alphanumeric by default (ADR 0012: the format in effect since July
  # 2026); pass alphanumeric: false for the still-valid legacy numeric one.
  def cnpj(alphanumeric: true)
    base = Array.new(12) { alphanumeric ? ALPHANUMERIC_CHARS.sample : rand(10).to_s }
    values = base.map { |char| char.ord - 48 }
    digits = check_digits(values, Catalog::DocumentNumber::CNPJ_FIRST_WEIGHTS, Catalog::DocumentNumber::CNPJ_SECOND_WEIGHTS)
    (base + digits.map(&:to_s)).join
  end

  def check_digits(values, first_weights, second_weights)
    first = Catalog::DocumentNumber.check_digit(values, first_weights)
    second = Catalog::DocumentNumber.check_digit(values + [ first ], second_weights)
    [ first, second ]
  end
end

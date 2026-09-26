module Catalog
  # Format and checksum validation for CPF and CNPJ (ADR 0012), including
  # the alphanumeric CNPJ in effect since July 2026 (Receita Federal
  # Instrucao Normativa RFB 2.229/2024): the first 12 characters may be
  # digits or upper-case letters, the two check digits stay numeric, and
  # the modulo 11 algorithm runs on each character's ASCII value minus 48
  # (a digit's ASCII-48 value equals the digit itself, so the classic
  # all-numeric CNPJ is just the special case with no letters). Verified
  # against Receita Federal's own published worked example: base
  # 12ABC34501DE checks out to 35 (see spec/models/catalog/document_number_spec.rb).
  class DocumentNumber
    CPF_LENGTH = 11
    CNPJ_LENGTH = 14

    CPF_FIRST_WEIGHTS = [ 10, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
    CPF_SECOND_WEIGHTS = [ 11, 10, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
    CNPJ_FIRST_WEIGHTS = [ 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
    CNPJ_SECOND_WEIGHTS = [ 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze

    def self.normalize(value)
      value.to_s.gsub(/[^0-9A-Za-z]/, "").upcase
    end

    # A CPF identifies a person, so a list or a viewer without the right to see
    # it gets the middle six digits only (the shape the government's own
    # portals use). A CNPJ is public registry data, so masking it would cost
    # usability and protect nothing.
    def self.mask(type, value)
      return value unless type.to_s == "cpf" && value.to_s.length == CPF_LENGTH

      "***#{value[3, 6]}**"
    end

    def self.valid?(type, value)
      case type.to_s
      when "cpf" then valid_cpf?(value)
      when "cnpj" then valid_cnpj?(value)
      else false
      end
    end

    def self.valid_cpf?(value)
      digits = normalize(value)
      return false unless digits.match?(/\A\d{#{CPF_LENGTH}}\z/)
      return false if digits.chars.uniq.one? # 000.000.000-00 .. 999.999.999-99 pass the checksum, never issued

      base = digits[0, 9].chars.map(&:to_i)
      first = check_digit(base, CPF_FIRST_WEIGHTS)
      second = check_digit(base + [ first ], CPF_SECOND_WEIGHTS)
      digits[9, 2] == "#{first}#{second}"
    end

    def self.valid_cnpj?(value)
      chars = normalize(value)
      return false unless chars.match?(/\A[0-9A-Z]{12}\d{2}\z/)
      return false if chars.match?(/\A(\d)\1{13}\z/) # same reasoning as the CPF repeated-digit guard

      values = chars[0, 12].chars.map { |char| char.ord - 48 }
      first = check_digit(values, CNPJ_FIRST_WEIGHTS)
      second = check_digit(values + [ first ], CNPJ_SECOND_WEIGHTS)
      chars[12, 2] == "#{first}#{second}"
    end

    # Public: DocumentNumberGenerator (lib/) reuses this to build fictitious,
    # valid numbers for seeds and specs.
    def self.check_digit(values, weights)
      remainder = values.zip(weights).sum { |value, weight| value * weight } % 11
      remainder < 2 ? 0 : 11 - remainder
    end
  end
end

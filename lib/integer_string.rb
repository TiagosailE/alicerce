# Strict whole numbers from a request (JSON integers and digit strings).
# Kernel#Integer without a base reads "010" as 8, "0x1A" as 26 and "1_0" as 10,
# which would silently store the wrong number of days on a payable term.
module IntegerString
  MAX_DIGITS = 18

  module_function

  # An Integer, or nil for anything that is not a plain base-10 whole number.
  def parse(raw)
    return raw if raw.is_a?(Integer)
    return nil unless raw.is_a?(String) && raw.match?(/\A-?\d{1,#{MAX_DIGITS}}\z/)

    Integer(raw, 10)
  end
end

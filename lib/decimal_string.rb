# Decimal strings for the API (ADR 0006): "1000.000000", "12.500". Always the
# full number of places, so a client never has to guess the scale and a JSON
# schema can state it as a pattern. Exact: no Float anywhere.
module DecimalString
  module_function

  def format(value, places)
    whole, fraction = value.to_d.round(places).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(places, "0")}"
  end

  # Strict parsing of what a client sends: digits with an optional fraction of
  # at most `places` digits and at most `integer_digits` before the point. A
  # value is never rounded to fit. Returns [BigDecimal, nil] or [nil, kind]
  # where kind is one of :not_a_number, :negative, :too_many_decimals,
  # :too_large, matching the error types the API reports.
  def parse(raw, places:, integer_digits:)
    text = raw.to_s.strip
    return [ nil, :negative ] if text.match?(/\A-\d/)
    return [ nil, :not_a_number ] unless text.match?(/\A\d+(\.\d+)?\z/)

    whole, fraction = text.split(".")
    return [ nil, :too_many_decimals ] if fraction.to_s.length > places
    return [ nil, :too_large ] if whole.sub(/\A0+(?=\d)/, "").length > integer_digits

    [ BigDecimal(text), nil ]
  end
end

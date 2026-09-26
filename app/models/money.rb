# Integer cents, and the one operation on them that is not plain arithmetic
# (ADR 0006): splitting a total into parts without losing or inventing a cent.
module Money
  module_function

  # Each part gets total / parts rounded down, and the first (total mod parts)
  # parts get one cent more. 10.001 in 3 is 3.334, 3.334, 3.333, which always
  # adds up to the total; the parts differ by at most one cent.
  def allocate(total_cents, parts)
    raise ArgumentError, "a total to split cannot be negative" if total_cents.negative?
    raise ArgumentError, "parts must be at least 1" if parts < 1

    base, extra = total_cents.divmod(parts)
    Array.new(parts) { |index| index < extra ? base + 1 : base }
  end
end

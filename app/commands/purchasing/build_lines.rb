module Purchasing
  # Turns what a client sent for an order's lines into OrderLine records, copying
  # from each product as it is now (ADR 0017), or reports every problem at once
  # with fields named "lines.0.quantity". Nothing is saved here.
  #
  # Returns [lines, fields]: fields is empty when every line is good.
  module BuildLines
    PRICE_CAP = Inventory::Ledger::VALUE_CAP_CENTS

    module_function

    def call(order:, inputs:)
      fields = {}
      unless inputs.is_a?(Array) && inputs.any?
        return [ [], { "lines" => [ "blank" ] } ]
      end
      return [ [], { "lines" => [ "too_many" ] } ] if inputs.size > Purchasing::Order::MAX_LINES

      lines = inputs.each_with_index.map { |input, index| build(order, input, index, fields) }
      [ lines, fields ]
    end

    def build(order, input, index, fields)
      input = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input.to_h
      input = input.with_indifferent_access
      report = ->(field, kind) { (fields["lines.#{index}.#{field}"] ||= []) << kind.to_s }

      line = Purchasing::OrderLine.new(order:, organization: order.organization, position: index + 1)
      product = input[:product_id].is_a?(Array) || input[:product_id].is_a?(Hash) ? nil : Catalog::Product.includes(:unit_conversion, :stock_unit).find_by(id: input[:product_id])
      if product.nil?
        report.call(:product_id, :not_found)
      elsif product.unit_conversion.nil?
        report.call(:product_id, :conversion_missing)
      else
        line.copy_from(product)
      end

      quantity, kind = DecimalString.parse(input[:quantity], places: Purchasing::OrderLine::QUANTITY_PLACES,
                                                                integer_digits: Purchasing::OrderLine::QUANTITY_INTEGER_DIGITS)
      kind ? report.call(:quantity, kind) : line.quantity = quantity

      price = whole_number(input[:unit_price_cents])
      if price.nil? || price.negative? || price > PRICE_CAP
        report.call(:unit_price_cents, price.nil? ? :not_a_number : :out_of_range)
      else
        line.unit_price_cents = price
      end

      discount = input[:discount_bp].nil? || input[:discount_bp] == "" ? 0 : whole_number(input[:discount_bp])
      if discount.nil? || !(0..10_000).cover?(discount)
        report.call(:discount_bp, discount.nil? ? :not_a_number : :out_of_range)
      else
        line.discount_bp = discount
      end

      # Amounts are worked out by the model; a value that does not fit the cap is the quantity's to answer for.
      if fields.keys.none? { |key| key.start_with?("lines.#{index}.") } && !line.valid?
        line.errors.each { |error| report.call(error.attribute, error.type) }
      end
      line
    end

    def whole_number(raw)
      return raw if raw.is_a?(Integer)
      return Integer(raw, 10) if raw.is_a?(String) && raw.match?(/\A-?\d+\z/)

      nil
    end
    private_class_method :build, :whole_number
  end
end

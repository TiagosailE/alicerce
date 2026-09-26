module Purchasing
  # What a client sent for a receipt, checked without touching the database
  # (ADR 0017): the lines as (order line, quantity) pairs, the date as a real
  # date not in the future in the organization's time zone, the supplier's
  # invoice number as short text. Every problem is reported at once, with fields
  # named "lines.0.quantity". What depends on rows (the line belongs to the
  # order, is not over-received, the date is not before the approval) is checked
  # by the command once it holds the locks.
  module ReceiptInput
    Item = Data.define(:index, :order_line_id, :quantity)
    Parsed = Data.define(:items, :received_on, :supplier_invoice_number)

    QUANTITY_PLACES = Purchasing::OrderLine::QUANTITY_PLACES
    QUANTITY_INTEGER_DIGITS = Purchasing::OrderLine::QUANTITY_INTEGER_DIGITS

    module_function

    # Returns [Parsed, fields]: fields is empty when everything is good.
    def call(lines:, received_on:, supplier_invoice_number:, time_zone:)
      fields = {}
      items = parse_lines(lines, fields)
      date = parse_date(received_on, time_zone, fields)
      invoice = supplier_invoice_number.presence
      if !invoice.nil? && !invoice.is_a?(String)
        fields["supplier_invoice_number"] = [ "invalid" ]
      elsif invoice && invoice.length > Purchasing::Receipt::SUPPLIER_INVOICE_MAX_LENGTH
        fields["supplier_invoice_number"] = [ "too_long" ]
      end

      [ Parsed.new(items:, received_on: date, supplier_invoice_number: invoice), fields ]
    end

    def parse_lines(inputs, fields)
      unless inputs.is_a?(Array) && inputs.any?
        fields["lines"] = [ "blank" ]
        return []
      end
      if inputs.size > Purchasing::Order::MAX_LINES
        fields["lines"] = [ "too_many" ]
        return []
      end

      seen = {}
      inputs.each_with_index.filter_map do |input, index|
        parse_line(input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input, index, fields, seen)
      end
    end

    def parse_line(input, index, fields, seen)
      unless input.is_a?(Hash)
        (fields["lines.#{index}"] ||= []) << "invalid"
        return
      end

      input = input.with_indifferent_access
      report = ->(field, kind) { (fields["lines.#{index}.#{field}"] ||= []) << kind.to_s }
      order_line_id = IntegerString.parse(input[:order_line_id])
      quantity, kind = DecimalString.parse(input[:quantity], places: QUANTITY_PLACES, integer_digits: QUANTITY_INTEGER_DIGITS)
      report.call(:order_line_id, :not_a_number) if order_line_id.nil?
      if kind
        report.call(:quantity, kind)
      elsif !quantity.positive?
        report.call(:quantity, :must_be_positive)
      end
      report.call(:order_line_id, :duplicate_line) if order_line_id && seen.key?(order_line_id)
      return if order_line_id.nil? || quantity.nil? || !quantity.positive? || seen.key?(order_line_id)

      seen[order_line_id] = true
      Item.new(index:, order_line_id:, quantity:)
    end

    # A day, as YYYY-MM-DD, in the organization's zone: what "today" means to
    # the person at the counter, not to the server.
    def parse_date(raw, time_zone, fields)
      if raw.blank?
        fields["received_on"] = [ "blank" ]
        return
      end

      date = raw.is_a?(String) && raw.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(raw) : nil
      if date.nil?
        fields["received_on"] = [ "invalid" ]
      elsif date > Time.current.in_time_zone(time_zone).to_date
        fields["received_on"] = [ "in_the_future" ]
      else
        date
      end
    rescue Date::Error
      fields["received_on"] = [ "invalid" ]
      nil
    end
  end
end

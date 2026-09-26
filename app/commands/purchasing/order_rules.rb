module Purchasing
  # Rules a purchase order must satisfy whenever it is created, edited or
  # approved (ADR 0017). Each returns a Hash of field errors, empty when fine.
  module OrderRules
    module_function

    def supplier_errors(supplier)
      return { "supplier_id" => [ "not_found" ] } if supplier.nil?
      return { "supplier_id" => [ "not_a_supplier" ] } unless supplier.supplier?
      return { "supplier_id" => [ "inactive" ] } unless supplier.active?

      {}
    end

    def total_errors(lines)
      total = lines.sum { |line| line.net_cents.to_i }
      total > Inventory::Ledger::VALUE_CAP_CENTS ? { "lines" => [ "total_too_large" ] } : {}
    end

    def total_cents(lines) = lines.sum { |line| line.net_cents.to_i }

    def copy_supplier(order, supplier)
      order.supplier = supplier
      order.supplier_name = supplier.name
      order.supplier_document_type = supplier.document_type
      order.supplier_document_number = supplier.document_number
    end
  end
end

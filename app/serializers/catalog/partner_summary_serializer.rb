module Catalog
  # The list shape (ADR 0014): what a table needs to recognize a partner.
  # A page of up to 100 of these must not become a bulk export of personal
  # data, so the CPF is masked and e-mail and phone are left out; the full
  # record is one request away for whoever may see it.
  class PartnerSummarySerializer
    def initialize(partner)
      @partner = partner
    end

    def as_json
      {
        id: @partner.id,
        name: @partner.name,
        document_type: @partner.document_type,
        document_number: Catalog::DocumentNumber.mask(@partner.document_type, @partner.document_number),
        customer: @partner.customer,
        supplier: @partner.supplier,
        active: @partner.active
      }
    end
  end
end

module Catalog
  class PartnerSerializer
    def initialize(partner)
      @partner = partner
    end

    def as_json
      {
        id: @partner.id,
        name: @partner.name,
        document_type: @partner.document_type,
        document_number: @partner.document_number,
        customer: @partner.customer,
        supplier: @partner.supplier,
        email: @partner.email,
        phone: @partner.phone,
        active: @partner.active
      }
    end
  end
end

module Catalog
  # The detail shape. personal_data_visible says whether the caller may see
  # the CPF, e-mail and phone in full (ADR 0014); when not, the CPF is masked
  # and the contact fields are null, and the flag lets the SPA say so instead
  # of showing "not informed" for data that exists but is hidden.
  class PartnerSerializer
    def initialize(partner, personal_data_visible:)
      @partner = partner
      @personal_data_visible = personal_data_visible
    end

    def as_json
      {
        id: @partner.id,
        name: @partner.name,
        document_type: @partner.document_type,
        document_number: document_number,
        customer: @partner.customer,
        supplier: @partner.supplier,
        email: (@partner.email if @personal_data_visible),
        phone: (@partner.phone if @personal_data_visible),
        personal_data_visible: @personal_data_visible,
        active: @partner.active,
        revision: @partner.revision
      }
    end

    private
      def document_number
        return @partner.document_number if @personal_data_visible

        Catalog::DocumentNumber.mask(@partner.document_type, @partner.document_number)
      end
  end
end

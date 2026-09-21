module Catalog
  # Error codes: :validation_failed.
  class CreatePartner
    def self.call(...) = new(...).call

    def initialize(organization:, name:, document_type:, document_number:, actor:, customer: false, supplier: false, email: nil, phone: nil)
      @organization = organization
      @name = name
      @document_type = document_type
      @document_number = document_number
      @customer = customer
      @supplier = supplier
      @email = email
      @phone = phone
      @actor = actor
    end

    def call
      result = nil

      ApplicationRecord.transaction do
        partner = Catalog::Partner.new(
          organization: @organization, name: @name, document_type: @document_type, document_number: @document_number,
          customer: @customer, supplier: @supplier, email: @email, phone: @phone
        )
        unless partner.save
          result = Result.invalid(partner)
          raise ActiveRecord::Rollback
        end

        changes = { document_type: partner.document_type, customer: partner.customer, supplier: partner.supplier }
        Catalog::Partner::PERSONAL_DATA_FIELDS.each { |field| changes[field] = "changed" if partner[field].present? }
        Audit.record("partner_created", partner, actor: @actor, changes:)
        result = Result.success(partner)
      end

      result
    end
  end
end

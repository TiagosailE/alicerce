module Catalog
  class Partner < ApplicationRecord
    include TenantScoped
    include RaceSafeUniqueness

    DOCUMENT_TYPES = %w[cpf cnpj].freeze

    # Recorded in the audit trail as changed, never with values (ADR 0010,
    # ADR 0012): a partner's own name is personal data exactly like a
    # user's, not only the document number.
    PERSONAL_DATA_FIELDS = %w[name document_number email phone].freeze

    encrypts :document_number, deterministic: true

    before_validation :normalize_document_number

    validates :name, presence: true
    validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
    validates :document_number, presence: true, uniqueness: { scope: :organization_id }
    validate :document_number_is_valid
    validate :customer_or_supplier

    private
      def normalize_document_number
        self.document_number = DocumentNumber.normalize(document_number) if document_number.present?
      end

      def document_number_is_valid
        return if document_type.blank? || document_number.blank?

        errors.add(:document_number, :invalid) unless DocumentNumber.valid?(document_type, document_number)
      end

      def customer_or_supplier
        errors.add(:base, :must_be_customer_or_supplier) unless customer? || supplier?
      end
  end
end

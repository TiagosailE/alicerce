# The next number of a document type, per organization (ADR 0017). A counter is
# the last row taken in ADR 0004's lock order: call next! as the final step of
# the command that creates the document, inside its transaction.
class DocumentCounter < ApplicationRecord
  include TenantScoped

  KINDS = %w[purchase_order receipt].freeze
  UNIQUE_INDEX = "index_document_counters_on_organization_and_kind".freeze

  # The row is created on first use (ON CONFLICT DO NOTHING, so two first users
  # do not collide), then incremented by a single UPDATE, which takes its lock
  # and returns the new value in one round trip. The lock is held until the
  # caller's transaction ends: a rollback gives the number back.
  def self.next!(organization:, kind:)
    raise ArgumentError, "unknown document kind #{kind.inspect}" unless KINDS.include?(kind)

    insert({ organization_id: organization.id, kind:, last_value: 0 }, unique_by: UNIQUE_INDEX)
    connection.select_value(sanitize_sql_array([
      "UPDATE document_counters SET last_value = last_value + 1, updated_at = now() " \
      "WHERE organization_id = ? AND kind = ? RETURNING last_value", organization.id, kind
    ])).to_i
  end
end

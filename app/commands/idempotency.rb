require "digest"

# Idempotency for critical writes (ADR 0005). A command calls claim inside its
# transaction, right after the lock timeout (ADR 0004):
#
#   claim = Idempotency.claim(organization:, user:, key:, request_digest:)
#   return replay(claim) if claim.replay?
#   return Result.failure(:idempotency_key_reused) if claim.reused?
#   ...do the effect...
#   claim.complete!(status: 201, resource: created_record)
#
# The insert waits on the unique index when a concurrent request holds the same
# key uncommitted; when that one rolls back the insert proceeds, when it
# commits the insert conflicts and the committed row is read instead. Failure
# paths roll the transaction back, which removes the key with the attempt.
module Idempotency
  KEY_FORMAT = /\A[A-Za-z0-9._:-]{8,100}\z/

  class Claim
    attr_reader :record

    def initialize(record, state)
      @record = record
      @state = state
    end

    def fresh? = @state == :fresh
    def replay? = @state == :replay
    def reused? = @state == :reused

    def complete!(status:, resource:)
      record.update!(response_status: status, resource_type: resource.class.name, resource_id: resource.id)
    end
  end

  module_function

  def valid_key?(key) = key.to_s.match?(KEY_FORMAT)

  # SHA-256 over the method, the path and the body with keys sorted at every
  # level, so the same request always digests the same and a different one
  # never does.
  def digest(method:, path:, params:)
    Digest::SHA256.hexdigest([ method.to_s.upcase, path, JSON.generate(canonical(params)) ].join("\n"))
  end

  def claim(organization:, user:, key:, request_digest:)
    inserted = IdempotencyKey.insert(
      { organization_id: organization.id, user_id: user.id, key:, request_digest: },
      unique_by: "index_idempotency_keys_on_organization_user_and_key", returning: %w[id]
    ).rows.first

    return Claim.new(IdempotencyKey.find(inserted.first), :fresh) if inserted

    existing = IdempotencyKey.find_by!(organization:, user:, key:)
    Claim.new(existing, existing.request_digest == request_digest ? :replay : :reused)
  end

  def canonical(value)
    case value
    when Hash then value.sort_by { |key, _| key.to_s }.to_h { |key, nested| [ key.to_s, canonical(nested) ] }
    when Array then value.map { |nested| canonical(nested) }
    else value
    end
  end
  private_class_method :canonical
end

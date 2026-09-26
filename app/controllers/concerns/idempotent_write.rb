# What a critical write needs from its controller (ADR 0005): the Idempotency-Key
# header, checked before the command runs, and a digest of what the request
# actually asked for, so the same key on a different request is refused.
module IdempotentWrite
  extend ActiveSupport::Concern

  private
    def require_idempotency_key!
      @idempotency_key = request.headers["Idempotency-Key"]
      return if Idempotency.valid_key?(@idempotency_key)

      render_error(status: :bad_request, code: "idempotency_key_required",
        message: "Send an Idempotency-Key header of 8 to 100 characters (letters, digits, . _ : -)")
    end

    # Digests what the action actually reads: params merges the query string
    # into the body, so a request that differs only in its query string is
    # a different request. The routing keys are in the path already.
    def request_digest
      Idempotency.digest(method: request.request_method, path: request.path,
        params: request.parameters.except(*request.path_parameters.keys.map(&:to_s)))
    end
end

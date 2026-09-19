# The signed-in identity for the request, set once in Api::V1::BaseController
# after the session cookie resolves, plus the request context Audit.record
# needs (ADR 0010). Reset automatically after every request.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :organization, :request_id, :ip_prefix
end

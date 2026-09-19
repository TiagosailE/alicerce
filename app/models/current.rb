# The signed-in identity for the request, set once in Api::V1::BaseController
# after the session cookie resolves. Reset automatically after every request.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :organization
end

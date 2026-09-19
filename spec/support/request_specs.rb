RSpec.configure do |config|
  # __Host- cookies (ADR 0007) are Secure; rack-test only resends a Secure
  # cookie on an https request, so request specs run as https to round-trip
  # them the same way a real browser does in production.
  config.before(:each, type: :request) { https! }

  # rate_limit (ADR 0007) counts in Rails.cache, which transactional
  # fixtures do not roll back; without this, counts leak between examples.
  config.before(:each) { Rails.cache.clear }
end

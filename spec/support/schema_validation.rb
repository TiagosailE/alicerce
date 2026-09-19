require "committee"

# Validates request spec responses against docs/openapi/openapi.yaml (ADR
# 0011): call assert_response_schema_confirm(status) after each request.
module SchemaValidation
  include Committee::Test::Methods

  SCHEMA_PATH = Rails.root.join("docs/openapi/openapi.yaml").to_s

  def committee_options
    @committee_options ||= { schema_path: SCHEMA_PATH, prefix: "/api/v1", strict_reference_validation: true }
  end

  def request_object
    request
  end

  def response_data
    [ response.status, response.headers, response.body ]
  end

  # Committee::Test::Methods memoizes the validator per request_object; a
  # request spec makes several requests per example, so it must be rebuilt
  # for each assertion instead of reusing the first request it saw.
  def schema_validator
    router.build_schema_validator(request_object)
  end
end

RSpec.configure do |config|
  config.include SchemaValidation, type: :request
end

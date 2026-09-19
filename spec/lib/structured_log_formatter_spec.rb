require "rails_helper"

RSpec.describe StructuredLogFormatter do
  subject(:formatter) { described_class.new }

  let(:time) { Time.utc(2026, 3, 1, 12, 30, 45, 123_456) }

  it "emits one JSON object per line with severity, time and message" do
    line = formatter.call("INFO", time, nil, "hello")

    expect(JSON.parse(line)).to eq("severity" => "INFO", "time" => "2026-03-01T12:30:45.123Z", "message" => "hello")
  end

  it "merges a hash message as top-level fields instead of stringifying it" do
    line = formatter.call("WARN", time, nil, { event: "sign_in_failed", email_digest: "abc123" })
    json = JSON.parse(line)

    expect(json).to include("severity" => "WARN", "event" => "sign_in_failed", "email_digest" => "abc123")
    expect(json).not_to have_key("message")
  end

  it "tags the line with the current request, user and organization when known" do
    Current.request_id = "req-123"
    Current.user = instance_double(Identity::User, id: 42)
    Current.organization = instance_double(Identity::Organization, id: 7)

    line = formatter.call("INFO", time, nil, "hello")

    expect(JSON.parse(line)).to include("request_id" => "req-123", "user_id" => 42, "organization_id" => 7)
  end

  it "omits the request, user and organization fields when none is known" do
    line = formatter.call("INFO", time, nil, "hello")

    json = JSON.parse(line)
    expect(json.keys).not_to include("request_id", "user_id", "organization_id")
  end
end

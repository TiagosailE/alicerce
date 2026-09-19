require "rails_helper"

RSpec.describe Audit do
  describe ".record" do
    it "creates an event from Current context, with the caller's action, subject and changes" do
      organization = create(:organization)
      actor = create(:user)
      set_current_tenant(organization)
      Current.request_id = "req-123"
      Current.ip_prefix = "203.0.113.0/24"

      event = described_class.record("signed_in", actor, actor:, changes: { "foo" => "bar" })

      expect(event).to be_persisted
      expect(event.organization).to eq(organization)
      expect(event.actor).to eq(actor)
      expect(event.action).to eq("signed_in")
      expect(event.subject_type).to eq("Identity::User")
      expect(event.subject_id).to eq(actor.id)
      expect(event.field_changes).to eq("foo" => "bar")
      expect(event.request_id).to eq("req-123")
      expect(event.ip_prefix).to eq("203.0.113.0/24")
    end

    it "defaults to no changes" do
      organization = create(:organization)
      actor = create(:user)
      set_current_tenant(organization)

      event = described_class.record("signed_in", actor, actor:)

      expect(event.field_changes).to eq({})
    end
  end

  describe ".ip_prefix" do
    it "keeps the /24 of an IPv4 address" do
      expect(described_class.ip_prefix("203.0.113.42")).to eq("203.0.113.0/24")
    end

    it "keeps the /48 of an IPv6 address" do
      expect(described_class.ip_prefix("2001:db8:abcd:12::1")).to eq("2001:db8:abcd::/48")
    end

    it "is nil for a blank or invalid address" do
      expect(described_class.ip_prefix(nil)).to be_nil
      expect(described_class.ip_prefix("")).to be_nil
      expect(described_class.ip_prefix("not-an-ip")).to be_nil
    end
  end
end

require "rails_helper"

RSpec.describe Identity::Session do
  let(:membership) { create(:membership) }
  let(:start) { Time.zone.parse("2026-09-21 08:00") }

  def start_session(user: membership.user, now: start)
    described_class.start!(user:, organization: membership.organization, ip: "203.0.113.7", user_agent: "Firefox", now:)
  end

  it "stores only a digest of the token" do
    session, token = start_session

    expect(session.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(token))
    expect(described_class.where(token_digest: token)).to be_empty
  end

  it "resumes a live session by its token and refreshes activity at most once a minute" do
    session, token = start_session

    expect(described_class.resume(token, now: start + 30.seconds)).to eq(session)
    expect(session.reload.last_seen_at).to eq(start)

    described_class.resume(token, now: start + 2.minutes)
    expect(session.reload.last_seen_at).to eq(start + 2.minutes)
  end

  it "expires after 30 minutes without activity and deletes itself" do
    _session, token = start_session

    expect(described_class.resume(token, now: start + 30.minutes)).to be_nil
    expect(described_class.count).to eq(0)
  end

  it "expires 12 hours after sign-in even with constant activity" do
    session, token = start_session
    session.update_column(:last_seen_at, start + 11.hours + 59.minutes)

    expect(described_class.resume(token, now: start + 12.hours)).to be_nil
  end

  it "ignores unknown and empty tokens" do
    expect(described_class.resume("nope")).to be_nil
    expect(described_class.resume("")).to be_nil
  end

  it "does not store the IP or user agent of demo users" do
    demo = create(:user, demo: true)
    create(:membership, user: demo, organization: membership.organization)

    session, _token = start_session(user: demo)

    expect(session.ip).to be_nil
    expect(session.user_agent).to be_nil
  end
end

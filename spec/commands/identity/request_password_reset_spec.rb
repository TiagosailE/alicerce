require "rails_helper"

RSpec.describe Identity::RequestPasswordReset do
  # The command itself never looks the account up (a security review found
  # that doing so, and enqueuing only for a real, non-demo account, leaked
  # that distinction through response timing); Identity::PasswordResetMailerJob
  # is covered separately for what it does once it runs.

  it "always enqueues the mailer job with the given email" do
    expect { described_class.call(email: "pessoa@alicerce.example") }
      .to have_enqueued_job(Identity::PasswordResetMailerJob).with(email: "pessoa@alicerce.example")
  end

  it "enqueues the same way for an unknown email as for a real one" do
    expect { described_class.call(email: "ninguem@alicerce.example") }
      .to have_enqueued_job(Identity::PasswordResetMailerJob).with(email: "ninguem@alicerce.example")
  end

  it "answers success in every case" do
    expect(described_class.call(email: "qualquer@alicerce.example")).to be_success
  end
end

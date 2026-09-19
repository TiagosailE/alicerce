require "rails_helper"

RSpec.describe Identity::PasswordResetMailerJob do
  around do |example|
    original = ENV["APP_HOST"]
    ENV["APP_HOST"] = "alicerce.example.com"
    example.run
    ENV["APP_HOST"] = original
  end

  it "does not log its arguments, since the email is the only one" do
    expect(described_class.log_arguments?).to be(false)
  end

  it "delivers a link to the user's email through Brevo, with a freshly generated token" do
    user = create(:user, name: "Joana Lima")

    expect(BrevoClient).to receive(:deliver) do |to:, to_name:, subject:, html_content:|
      expect(to).to eq(user.email)
      expect(to_name).to eq("Joana Lima")
      expect(subject).to include("senha")
      expect(html_content).to include("https://alicerce.example.com/redefinir-senha?token=")
      expect(Identity::User.find_by_password_reset_token(html_content[/token=([^"<]+)/, 1])).to eq(user)
    end

    described_class.perform_now(email: user.email)
  end

  it "escapes the user's name in the email body" do
    user = create(:user, name: "<script>alert(1)</script>")

    expect(BrevoClient).to receive(:deliver) do |html_content:, **_rest|
      expect(html_content).not_to include("<script>alert(1)</script>")
    end

    described_class.perform_now(email: user.email)
  end

  it "does nothing for an unknown email" do
    expect(BrevoClient).not_to receive(:deliver)

    described_class.perform_now(email: "ninguem@alicerce.example")
  end

  it "does nothing for a demo account (ADR 0008)" do
    demo_user = create(:user, demo: true)

    expect(BrevoClient).not_to receive(:deliver)

    described_class.perform_now(email: demo_user.email)
  end
end

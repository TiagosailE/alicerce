require "rails_helper"

RSpec.describe Identity::CompletePasswordReset do
  it "fails with invalid_token for an unknown token" do
    result = described_class.call(token: "not-a-real-token", password: "nova-senha-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_token)
  end

  it "fails with invalid_token for an expired token" do
    user = create(:user)
    token = travel_to(21.minutes.ago) { user.password_reset_token }

    result = described_class.call(token:, password: "nova-senha-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_token)
  end

  it "fails with invalid_token for a demo account's token (ADR 0008)" do
    demo_user = create(:user, demo: true)
    token = demo_user.password_reset_token

    result = described_class.call(token:, password: "nova-senha-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_token)
    expect(demo_user.reload.authenticate("nova-senha-longa")).to be(false)
  end

  it "sets the new password and returns the user" do
    user = create(:user, password: "senha-antiga-e-longa")
    token = user.password_reset_token

    result = described_class.call(token:, password: "nova-senha-bem-longa")

    expect(result).to be_success
    expect(result.value).to eq(user)
    expect(user.reload.authenticate("nova-senha-bem-longa")).to eq(user)
  end

  it "fails with validation_failed when the new password is too short" do
    user = create(:user)
    token = user.password_reset_token

    result = described_class.call(token:, password: "curta")

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
  end

  it "invalidates the token after use, since it is bound to the password salt" do
    user = create(:user)
    token = user.password_reset_token

    first_attempt = described_class.call(token:, password: "primeira-troca-longa")
    second_attempt = described_class.call(token:, password: "segunda-troca-longa")

    expect(first_attempt).to be_success

    expect(second_attempt).not_to be_success
    expect(second_attempt.error).to eq(:invalid_token)
  end

  it "revokes every session the user holds, in every organization" do
    user = create(:user)
    organization = create(:organization)
    create(:membership, organization:, user:, role: "owner")
    Identity::Session.start!(user:, organization:, ip: "203.0.113.9", user_agent: "spec")
    token = user.password_reset_token

    described_class.call(token:, password: "nova-senha-bem-longa")

    expect(Identity::Session.count).to eq(0)
  end
end

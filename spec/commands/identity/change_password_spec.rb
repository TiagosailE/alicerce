require "rails_helper"

RSpec.describe Identity::ChangePassword do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, password: "senha-antiga-e-longa") }

  before do
    set_current_tenant(organization)
    create(:membership, organization:, user:, role: "owner")
  end

  it "fails with invalid_current_password when the current password is wrong" do
    result = described_class.call(user:, current_password: "senha-errada", new_password: "nova-senha-bem-longa")

    expect(result).not_to be_success
    expect(result.error).to eq(:invalid_current_password)
    expect(user.reload.authenticate("senha-antiga-e-longa")).to eq(user)
  end

  it "sets the new password" do
    result = described_class.call(user:, current_password: "senha-antiga-e-longa", new_password: "nova-senha-bem-longa")

    expect(result).to be_success
    expect(user.reload.authenticate("nova-senha-bem-longa")).to eq(user)
  end

  it "fails with validation_failed when the new password is too short" do
    result = described_class.call(user:, current_password: "senha-antiga-e-longa", new_password: "curta")

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(user.reload.authenticate("senha-antiga-e-longa")).to eq(user)
  end

  it "records a password_changed audit event" do
    described_class.call(user:, current_password: "senha-antiga-e-longa", new_password: "nova-senha-bem-longa")

    event = Audit::Event.sole
    expect(event.action).to eq("password_changed")
    expect(event.actor).to eq(user)
    expect(event.subject_type).to eq("Identity::User")
    expect(event.subject_id).to eq(user.id)
  end

  it "revokes every other session the user holds, in every organization" do
    _here, here_token = Identity::Session.start!(user:, organization:, ip: "203.0.113.9", user_agent: "spec")
    other_organization = create(:organization)
    create(:membership, organization: other_organization, user:, role: "read_only")
    Identity::Session.start!(user:, organization: other_organization, ip: "203.0.113.9", user_agent: "spec")

    described_class.call(user:, current_password: "senha-antiga-e-longa", new_password: "nova-senha-bem-longa")

    expect(Identity::Session.count).to eq(0)
  end

  it "keeps the acting session alive" do
    acting_session, = Identity::Session.start!(user:, organization:, ip: "203.0.113.9", user_agent: "spec")

    result = described_class.call(
      user:, current_password: "senha-antiga-e-longa", new_password: "nova-senha-bem-longa", acting_session:
    )

    expect(result).to be_success
    expect(Identity::Session.exists?(acting_session.id)).to be(true)
  end
end

require "rails_helper"

RSpec.describe Identity::User do
  it "normalizes the email and treats it as case insensitive" do
    create(:user, email: "  Joana.Lima@Canion.Example ")

    duplicate = build(:user, email: "joana.lima@canion.example")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.details[:email]).to include(a_hash_including(error: :taken))
  end

  it "rejects passwords shorter than 12 characters" do
    user = build(:user, password: "curta-demais")
    expect(user).to be_valid

    user.password = "onze-chars!"
    expect(user).not_to be_valid
  end

  it "rejects passwords above the 72 byte bcrypt limit, counting bytes, not characters" do
    user = build(:user, password: "ç" * 37)

    expect(user).not_to be_valid
    expect(user.errors.details[:password]).to include(a_hash_including(error: :password_too_long))
  end

  it "authenticates with the right password only" do
    user = create(:user, password: "senha-certa-e-longa")

    expect(user.authenticate("senha-certa-e-longa")).to eq(user)
    expect(user.authenticate("senha-errada-e-longa")).to be(false)
  end

  describe "#password_reset_token (ADR 0007)" do
    it "resolves back to the user through find_by_password_reset_token" do
      user = create(:user)

      expect(Identity::User.find_by_password_reset_token(user.password_reset_token)).to eq(user)
    end

    it "expires after 20 minutes" do
      user = create(:user)
      now = Time.current
      token = travel_to(now) { user.password_reset_token }

      travel_to(now + 19.minutes) { expect(Identity::User.find_by_password_reset_token(token)).to eq(user) }
      travel_to(now + 21.minutes) { expect(Identity::User.find_by_password_reset_token(token)).to be_nil }
    end

    it "stops working once the password changes, since it is bound to the salt" do
      user = create(:user)
      token = user.password_reset_token

      user.update!(password: "outra-senha-bem-longa")

      expect(Identity::User.find_by_password_reset_token(token)).to be_nil
    end
  end

  describe ".email_digest" do
    it "hashes a normalized form of the email, so casing and spacing do not change it" do
      expect(Identity::User.email_digest("  Pessoa@Alicerce.Example ")).to eq(Identity::User.email_digest("pessoa@alicerce.example"))
    end

    it "never returns the email itself" do
      expect(Identity::User.email_digest("pessoa@alicerce.example")).not_to include("pessoa")
    end
  end
end

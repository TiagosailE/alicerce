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
end

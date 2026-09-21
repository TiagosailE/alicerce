require "rails_helper"

RSpec.describe Catalog::Category do
  let(:organization) { create(:organization) }

  it "requires a name" do
    set_current_tenant(organization)
    category = build(:category, organization:, name: "")

    expect(category).not_to be_valid
    expect(category.errors.of_kind?(:name, :blank)).to be(true)
  end

  it "rejects a duplicate name within the same organization, regardless of case" do
    set_current_tenant(organization)
    create(:category, organization:, name: "Cimento e argamassa")
    duplicate = build(:category, organization:, name: "CIMENTO E ARGAMASSA")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:name, :taken)).to be(true)
  end
end

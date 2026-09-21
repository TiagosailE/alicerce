require "rails_helper"

RSpec.describe Catalog::Unit do
  let(:organization) { create(:organization) }

  it "requires a code and a name" do
    set_current_tenant(organization)
    unit = build(:unit, organization:, code: "", name: "")

    expect(unit).not_to be_valid
    expect(unit.errors.of_kind?(:code, :blank)).to be(true)
    expect(unit.errors.of_kind?(:name, :blank)).to be(true)
  end

  it "rejects a duplicate code within the same organization" do
    set_current_tenant(organization)
    create(:unit, organization:, code: "SC")
    duplicate = build(:unit, organization:, code: "SC")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:code, :taken)).to be(true)
  end

  it "allows the same code in a different organization" do
    other_organization = create(:organization)
    set_current_tenant(organization)
    create(:unit, organization:, code: "SC")

    set_current_tenant(other_organization)
    same_code_elsewhere = build(:unit, organization: other_organization, code: "SC")

    expect(same_code_elsewhere).to be_valid
  end
end

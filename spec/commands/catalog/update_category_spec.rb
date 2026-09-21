require "rails_helper"

RSpec.describe Catalog::UpdateCategory do
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }

  before { set_current_tenant(organization) }

  it "updates the category's fields" do
    category = create(:category, organization:, name: "Ferragens")

    result = described_class.call(category:, attributes: { name: "Ferragens e fixação", active: true }, actor:)

    expect(result).to be_success
    expect(category.reload.name).to eq("Ferragens e fixação")
  end

  it "can deactivate a category" do
    category = create(:category, organization:, active: true)

    result = described_class.call(category:, attributes: { name: category.name, active: false }, actor:)

    expect(result).to be_success
    expect(category.reload.active).to be(false)
  end

  it "fails with validation_failed for a duplicate name" do
    create(:category, organization:, name: "Agregados")
    category = create(:category, organization:, name: "Ferragens")

    result = described_class.call(category:, attributes: { name: "agregados", active: true }, actor:)

    expect(result).not_to be_success
    expect(result.error).to eq(:validation_failed)
    expect(category.reload.name).to eq("Ferragens")
  end
end

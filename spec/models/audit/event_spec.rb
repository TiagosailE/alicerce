require "rails_helper"

RSpec.describe Audit::Event do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:actor) { create(:user) }

  it "raises when queried with no current organization" do
    expect { described_class.count }.to raise_error(TenantScoped::NoTenantError)
  end

  it "only lists events of the current organization" do
    set_current_tenant(organization)
    mine = create(:audit_event, organization:, actor:)

    set_current_tenant(other_organization)
    create(:audit_event, organization: other_organization, actor:)

    set_current_tenant(organization)
    expect(described_class.all).to contain_exactly(mine)
  end

  it "stays invisible to another organization even bypassing the default scope" do
    set_current_tenant(organization)
    create(:audit_event, organization:, actor:)

    set_current_tenant(other_organization)
    expect(described_class.unscoped.where(organization: organization)).to be_empty
  end

  it "requires an action, a subject type and a subject id" do
    set_current_tenant(organization)
    event = described_class.new(organization:, actor:)

    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to contain_exactly(:action, :subject_type, :subject_id)
  end
end

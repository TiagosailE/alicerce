require "rails_helper"

RSpec.describe "Audit events constraints" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:organization) { create(:organization) }
  let(:actor) { create(:user) }
  let!(:event) do
    set_current_tenant(organization)
    create(:audit_event, organization:, actor:)
  end

  # A failed raw statement aborts the surrounding transaction; wrapping it in
  # its own savepoint (requires_new: true) lets Rails roll back just that
  # savepoint when the expected error propagates, leaving the transactional
  # fixture healthy for the rest of the example.
  it "rejects UPDATE even from the app role" do
    expect {
      connection.transaction(requires_new: true) do
        connection.execute("UPDATE audit_events SET action = 'tampered' WHERE id = #{event.id}")
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end

  it "rejects DELETE even from the app role" do
    expect {
      connection.transaction(requires_new: true) do
        connection.execute("DELETE FROM audit_events WHERE id = #{event.id}")
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end

  it "hides another organization's events" do
    other_organization = create(:organization)
    set_current_tenant(other_organization)

    expect(connection.select_value("SELECT count(*) FROM audit_events WHERE id = #{event.id}").to_i).to eq(0)
  end

  it "purges an organization's events older than a date through audit_purge, leaving newer ones" do
    old_event = create(:audit_event, organization:, actor:, created_at: 6.years.ago)

    purged = connection.select_value("SELECT audit_purge(#{organization.id}, now() - interval '5 years')")

    expect(purged.to_i).to eq(1)
    set_current_tenant(organization)
    expect(Audit::Event.where(id: old_event.id)).to be_empty
    expect(Audit::Event.where(id: event.id)).to exist
  end

  it "does not purge another organization's events" do
    other_organization = create(:organization)
    set_current_tenant(other_organization)
    other_old_event = create(:audit_event, organization: other_organization, actor:, created_at: 6.years.ago)

    connection.execute("SELECT audit_purge(#{organization.id}, now())")

    set_current_tenant(other_organization)
    expect(Audit::Event.where(id: other_old_event.id)).to exist
  end

  it "redacts an event's field_changes through audit_redact" do
    redacted = connection.select_value(
      "SELECT audit_redact(#{organization.id}, #{connection.quote(event.subject_type)}, #{event.subject_id})"
    )

    expect(redacted.to_i).to eq(1)
    set_current_tenant(organization)
    expect(event.reload.field_changes).to eq("redacted" => true)
  end
end

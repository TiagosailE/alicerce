require "rails_helper"

RSpec.describe DocumentCounter do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  before { set_current_tenant(organization) }

  describe ".next!" do
    it "counts from 1, in order" do
      expect(3.times.map { described_class.next!(organization:, kind: "receipt") }).to eq([ 1, 2, 3 ])
    end

    it "keeps each kind and each organization on its own sequence" do
      described_class.next!(organization:, kind: "receipt")
      described_class.next!(organization:, kind: "receipt")

      expect(described_class.next!(organization:, kind: "purchase_order")).to eq(1)
      set_current_tenant(other_organization)
      expect(described_class.next!(organization: other_organization, kind: "receipt")).to eq(1)
    end

    it "gives a number back when the transaction that took it rolls back" do
      described_class.next!(organization:, kind: "receipt")

      ApplicationRecord.transaction(requires_new: true) do
        expect(described_class.next!(organization:, kind: "receipt")).to eq(2)
        raise ActiveRecord::Rollback
      end

      expect(described_class.next!(organization:, kind: "receipt")).to eq(2)
    end

    it "refuses a kind it does not know" do
      expect { described_class.next!(organization:, kind: "invoice") }.to raise_error(ArgumentError, /unknown document kind/)
    end
  end

  it "hides another organization's counter and refuses to write one for it (row level security)" do
    described_class.next!(organization:, kind: "receipt")
    connection = ActiveRecord::Base.connection
    id = connection.select_value("SELECT id FROM document_counters LIMIT 1")

    set_current_tenant(other_organization)
    expect(connection.select_value("SELECT count(*) FROM document_counters WHERE id = #{id}").to_i).to eq(0)
    expect do
      connection.transaction(requires_new: true) do
        connection.execute("INSERT INTO document_counters (organization_id, kind, created_at, updated_at) VALUES (#{organization.id}, 'receipt', now(), now())")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end

  it "never goes negative and only knows the documents that exist" do
    connection = ActiveRecord::Base.connection

    expect do
      connection.transaction(requires_new: true) do
        connection.execute("INSERT INTO document_counters (organization_id, kind, last_value, created_at, updated_at) VALUES (#{organization.id}, 'receipt', -1, now(), now())")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /document_counters_last_value_not_negative/)
    expect do
      connection.transaction(requires_new: true) do
        connection.execute("INSERT INTO document_counters (organization_id, kind, created_at, updated_at) VALUES (#{organization.id}, 'invoice', now(), now())")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /document_counters_kind_valid/)
  end
end

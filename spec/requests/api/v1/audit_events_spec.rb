require "rails_helper"

RSpec.describe "Audit events API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_membership(organization, role:, demo: false)
    user = create(:user, password:, demo:)
    create(:membership, user:, organization:, role:)
    user
  end

  describe "GET /api/v1/audit_events" do
    it "requires an existing session" do
      get "/api/v1/audit_events"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # Role matrix (ADR 0008): only owner and admin view the audit trail.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :forbidden, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        sign_in_via_api(email: user.email, password:)

        get "/api/v1/audit_events"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "allows a demo owner to view the audit trail" do
      demo_owner = create_membership(organization, role: "owner", demo: true)
      sign_in_via_api(email: demo_owner.email, password:)

      get "/api/v1/audit_events"

      expect(response).to have_http_status(:ok)
    end

    it "lists only the current organization's events, newest first" do
      owner = create_membership(organization, role: "owner")
      sign_in_via_api(email: owner.email, password:) # itself an audit event, the most recent one

      set_current_tenant(organization)
      older = create(:audit_event, organization:, actor: owner, created_at: 2.days.ago)
      newer = create(:audit_event, organization:, actor: owner, created_at: 1.day.ago)

      set_current_tenant(other_organization)
      create(:audit_event, organization: other_organization, actor: create(:user))

      get "/api/v1/audit_events"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)

      body = response.parsed_body
      ids = body["data"].map { |event| event["id"] }
      expect(ids.last(2)).to eq([ newer.id, older.id ])
      expect(body["meta"]).to eq("page" => 1, "per_page" => 25, "total" => 3)
      expect(body["data"].first["action"]).to eq("signed_in")
    end

    it "paginates with page and per_page" do
      owner = create_membership(organization, role: "admin")
      sign_in_via_api(email: owner.email, password:) # itself an audit event

      set_current_tenant(organization)
      3.times { |n| create(:audit_event, organization:, actor: owner, created_at: (n + 1).days.ago) }

      get "/api/v1/audit_events", params: { page: 2, per_page: 2 }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["data"].length).to eq(2)
      expect(body["meta"]).to eq("page" => 2, "per_page" => 2, "total" => 4)
    end
  end
end

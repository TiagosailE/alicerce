require "rails_helper"

RSpec.describe "Session API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:user) { create(:user, password:) }
  let!(:membership) { create(:membership, user:, organization:, role: "owner") }

  def fetch_csrf_token
    get "/api/v1/session"
    assert_response_schema_confirm(200)
    response.parsed_body.dig("data", "csrf_token")
  end

  def sign_in(email:, password:, organization_id: nil, csrf_token: fetch_csrf_token)
    post "/api/v1/session",
      params: { email:, password:, organization_id: }.compact,
      as: :json,
      headers: { "X-CSRF-Token" => csrf_token }
  end

  def sign_out(csrf_token:)
    delete "/api/v1/session", headers: { "X-CSRF-Token" => csrf_token }
  end

  describe "GET /api/v1/session" do
    it "hands out a CSRF token with no one signed in" do
      get "/api/v1/session"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)

      data = response.parsed_body.fetch("data")
      expect(data["csrf_token"]).to be_a(String)
      expect(data).to include("user" => nil, "membership" => nil, "memberships" => [])
    end
  end

  describe "POST /api/v1/session" do
    it "refuses to sign in without the CSRF token from a prior GET" do
      post "/api/v1/session", params: { email: user.email, password: }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "refuses a CSRF token that does not match the session" do
      fetch_csrf_token
      post "/api/v1/session", params: { email: user.email, password: }, as: :json, headers: { "X-CSRF-Token" => "wrong-token" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "rejects wrong credentials the same way for an unknown email" do
      sign_in(email: user.email, password: "not-the-password")
      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")

      sign_in(email: "nobody@alicerce.example", password:)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    it "answers validation_failed when email or password is missing" do
      csrf_token = fetch_csrf_token
      post "/api/v1/session", params: { email: user.email }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "signs in and sets the session cookie when the user has one organization" do
      sign_in(email: user.email, password:)

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)

      data = response.parsed_body.fetch("data")
      expect(data.dig("user", "email")).to eq(user.email)
      expect(data.dig("membership", "role")).to eq("owner")
      expect(data.dig("membership", "organization", "id")).to eq(organization.id)
      expect(Identity::Session.count).to eq(1)
    end

    it "signs in a demo user without recording their IP or user agent" do
      demo_user = create(:user, demo: true, password:)
      create(:membership, user: demo_user, organization:, role: "owner")

      sign_in(email: demo_user.email, password:)

      expect(response).to have_http_status(:created)
      session = Identity::Session.sole
      expect(session.ip).to be_nil
      expect(session.user_agent).to be_nil
    end

    context "when the user belongs to more than one organization" do
      let(:other_organization) { create(:organization) }
      let!(:other_membership) { create(:membership, user:, organization: other_organization, role: "sales") }

      it "asks which organization to sign in to, listing all of them" do
        sign_in(email: user.email, password:)

        expect(response).to have_http_status(:unprocessable_content)
        assert_response_schema_confirm(422)

        body = response.parsed_body
        expect(body.dig("error", "code")).to eq("organization_required")
        organizations = body.dig("error", "details", "memberships").map { |m| m.dig("organization", "id") }
        expect(organizations).to contain_exactly(organization.id, other_organization.id)
      end

      it "signs in to the organization named in the request" do
        sign_in(email: user.email, password:, organization_id: other_organization.id)

        expect(response).to have_http_status(:created)
        data = response.parsed_body.fetch("data")
        expect(data.dig("membership", "organization", "id")).to eq(other_organization.id)
        expect(data.dig("membership", "role")).to eq("sales")
      end
    end

    it "rotates the session, deleting the previous row, on a second sign-in" do
      sign_in(email: user.email, password:)
      first_session_id = response.parsed_body.dig("data")
      expect(Identity::Session.count).to eq(1)
      first_token = Identity::Session.sole.token_digest

      sign_in(email: user.email, password:)

      expect(response).to have_http_status(:created)
      expect(Identity::Session.count).to eq(1)
      expect(Identity::Session.sole.token_digest).not_to eq(first_token)
      expect(first_session_id).to be_present
    end

    it "rate limits repeated attempts for the same IP and email" do
      5.times do
        sign_in(email: user.email, password: "not-the-password")
        expect(response).to have_http_status(:unauthorized)
      end

      sign_in(email: user.email, password: "not-the-password")

      expect(response).to have_http_status(:too_many_requests)
      assert_response_schema_confirm(429)
      expect(response.parsed_body.dig("error", "code")).to eq("rate_limited")
    end
  end

  describe "DELETE /api/v1/session" do
    it "requires an existing session even with a valid CSRF token" do
      csrf_token = fetch_csrf_token
      sign_out(csrf_token:)

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token" do
      sign_in(email: user.email, password:)
      delete "/api/v1/session"

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "signs out, deletes the session row and clears the cookie" do
      sign_in(email: user.email, password:)
      expect(Identity::Session.count).to eq(1)

      csrf_token = fetch_csrf_token
      sign_out(csrf_token:)

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      expect(Identity::Session.count).to eq(0)

      get "/api/v1/session"
      expect(response.parsed_body.dig("data", "user")).to be_nil
    end
  end

  describe "POST /api/v1/session/organization" do
    let(:other_organization) { create(:organization) }
    let!(:other_membership) { create(:membership, user:, organization: other_organization, role: "finance") }

    def switch_organization(organization_id:, csrf_token:)
      post "/api/v1/session/organization", params: { organization_id: }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
    end

    it "requires an existing session" do
      csrf_token = fetch_csrf_token
      switch_organization(organization_id: other_organization.id, csrf_token:)

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "switches to another organization the user belongs to, rotating the session" do
      sign_in(email: user.email, password:, organization_id: organization.id)
      previous_token = Identity::Session.sole.token_digest
      csrf_token = fetch_csrf_token

      switch_organization(organization_id: other_organization.id, csrf_token:)

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)

      data = response.parsed_body.fetch("data")
      expect(data.dig("membership", "organization", "id")).to eq(other_organization.id)
      expect(data.dig("membership", "role")).to eq("finance")
      expect(Identity::Session.count).to eq(1)
      expect(Identity::Session.sole.token_digest).not_to eq(previous_token)
    end

    it "answers not_found for an organization the user does not belong to" do
      outsider_organization = create(:organization)
      sign_in(email: user.email, password:, organization_id: organization.id)
      csrf_token = fetch_csrf_token

      switch_organization(organization_id: outsider_organization.id, csrf_token:)

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end
  end
end

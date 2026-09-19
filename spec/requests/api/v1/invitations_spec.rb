require "rails_helper"

RSpec.describe "Invitations API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_membership(organization, role:, demo: false)
    user = create(:user, password:, demo:)
    create(:membership, user:, organization:, role:)
    user
  end

  def sign_in_and_csrf(user)
    sign_in_via_api(email: user.email, password:)
    fetch_csrf_token
  end

  describe "POST /api/v1/invitations" do
    it "requires an existing session" do
      post "/api/v1/invitations", params: { email: "novo@alicerce.example", role: "sales" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token from a prior GET" do
      owner = create_membership(organization, role: "owner")
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/invitations", params: { email: "novo@alicerce.example", role: "sales" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): only owner and admin manage members.
    { "owner" => :created, "admin" => :created, "purchasing" => :forbidden, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        user = create_membership(organization, role:)
        csrf_token = sign_in_and_csrf(user)

        post "/api/v1/invitations", params: { email: "novo@alicerce.example", role: "sales" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "denies a demo owner (ADR 0008)" do
      demo_owner = create_membership(organization, role: "owner", demo: true)
      csrf_token = sign_in_and_csrf(demo_owner)

      post "/api/v1/invitations", params: { email: "novo@alicerce.example", role: "sales" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:forbidden)
    end

    it "issues an invitation with its one-time token, visible only to the current organization" do
      owner = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/invitations", params: { email: "novo@alicerce.example", role: "sales" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body.fetch("data")
      expect(data["email"]).to eq("novo@alicerce.example")
      expect(data["role"]).to eq("sales")
      expect(data["token"]).to be_a(String)

      set_current_tenant(organization)
      expect(Identity::Invitation.count).to eq(1)
      set_current_tenant(other_organization)
      expect(Identity::Invitation.count).to eq(0)
    end

    it "answers already_member when the email already belongs to the organization" do
      owner = create_membership(organization, role: "owner")
      existing = create(:user, email: "existente@alicerce.example")
      set_current_tenant(organization)
      create(:membership, organization:, user: existing, role: "sales")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/invitations", params: { email: "existente@alicerce.example", role: "finance" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("already_member")
    end
  end

  describe "POST /api/v1/invitations/acceptance" do
    # Issues the invitation as the owner, then drops the owner's session
    # cookie: whoever opens the link is a different visitor, not the same
    # browser that sent the invite.
    def invite(email: "convidado@alicerce.example", role: "sales")
      owner = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)
      post "/api/v1/invitations", params: { email:, role: }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      token = response.parsed_body.dig("data", "token")
      cookies.delete("__Host-session")
      token
    end

    it "registers a new account and joins the organization at the invited role, signing in" do
      token = invite
      csrf_token = fetch_csrf_token

      post "/api/v1/invitations/acceptance",
        params: { token:, name: "Pessoa Convidada", password: },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body.fetch("data")
      expect(data.dig("user", "email")).to eq("convidado@alicerce.example")
      expect(data.dig("membership", "role")).to eq("sales")
      expect(data.dig("membership", "organization", "id")).to eq(organization.id)
      expect(Identity::Session.count).to eq(2) # the inviting owner, plus the newly accepted member
    end

    it "joins an existing account without a name or password when that email already has one" do
      existing = create(:user, email: "convidado@alicerce.example", password:)
      token = invite(email: "convidado@alicerce.example")
      csrf_token = fetch_csrf_token

      post "/api/v1/invitations/acceptance", params: { token: }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      data = response.parsed_body.fetch("data")
      expect(data.dig("user", "id")).to eq(existing.id)
    end

    it "answers invalid_token for an unknown token" do
      csrf_token = fetch_csrf_token

      post "/api/v1/invitations/acceptance",
        params: { token: "not-a-real-token", name: "Pessoa", password: },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_token")
    end

    it "answers invalid_token for an already accepted invitation" do
      token = invite
      csrf_token = fetch_csrf_token
      post "/api/v1/invitations/acceptance", params: { token:, name: "Pessoa Convidada", password: }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      expect(response).to have_http_status(:created)

      post "/api/v1/invitations/acceptance",
        params: { token:, name: "Outra Pessoa", password: },
        as: :json, headers: { "X-CSRF-Token" => fetch_csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_token")
    end

    it "answers validation_failed when a new account is missing a name or password" do
      token = invite
      csrf_token = fetch_csrf_token

      post "/api/v1/invitations/acceptance", params: { token:, name: "" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "requires the CSRF token from a prior GET" do
      token = invite

      post "/api/v1/invitations/acceptance", params: { token:, name: "Pessoa", password: }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "records a signed_in audit event for the newly accepted member" do
      token = invite
      csrf_token = fetch_csrf_token

      post "/api/v1/invitations/acceptance", params: { token:, name: "Pessoa Convidada", password: }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      set_current_tenant(organization)
      new_user_id = response.parsed_body.dig("data", "user", "id")
      expect(Audit::Event.where(action: "signed_in", subject_id: new_user_id).count).to eq(1)
    end

    it "rate limits repeated attempts from the same IP" do
      token = invite

      10.times do
        csrf_token = fetch_csrf_token
        post "/api/v1/invitations/acceptance", params: { token:, name: "Pessoa", password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      end
      csrf_token = fetch_csrf_token
      post "/api/v1/invitations/acceptance", params: { token:, name: "Pessoa", password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:too_many_requests)
      assert_response_schema_confirm(429)
    end
  end
end

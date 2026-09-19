require "rails_helper"

RSpec.describe "Passwords API" do
  let(:password) { "senha-antiga-e-longa" }
  let(:organization) { create(:organization) }

  def create_membership(organization, role:, demo: false)
    user = create(:user, password:, demo:)
    create(:membership, user:, organization:, role:)
    user
  end

  def sign_in_and_csrf(user)
    sign_in_via_api(email: user.email, password:)
    fetch_csrf_token
  end

  describe "PATCH /api/v1/password" do
    it "requires an existing session" do
      patch "/api/v1/password", params: { current_password: password, password: "nova-senha-bem-longa" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token from a prior GET" do
      user = create_membership(organization, role: "owner")
      sign_in_via_api(email: user.email, password:)

      patch "/api/v1/password", params: { current_password: password, password: "nova-senha-bem-longa" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Any role may change their own password (no per-role variance beyond
    # the demo denial below), so this is a direct test rather than the
    # per-role matrix (spec/requests/api/v1/route_inventory_spec.rb).
    %w[owner admin purchasing sales finance read_only].each do |role|
      it "changes the #{role} role's own password" do
        user = create_membership(organization, role:)
        csrf_token = sign_in_and_csrf(user)

        patch "/api/v1/password", params: { current_password: password, password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(:no_content)
        assert_response_schema_confirm(204)
        expect(user.reload.authenticate("nova-senha-bem-longa")).to eq(user)
      end
    end

    it "denies a demo owner (ADR 0008)" do
      demo_owner = create_membership(organization, role: "owner", demo: true)
      csrf_token = sign_in_and_csrf(demo_owner)

      patch "/api/v1/password", params: { current_password: password, password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:forbidden)
      assert_response_schema_confirm(403)
      expect(demo_owner.reload.authenticate(password)).to eq(demo_owner)
    end

    it "answers invalid_current_password when the current password is wrong" do
      user = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(user)

      patch "/api/v1/password", params: { current_password: "senha-errada", password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_current_password")
    end

    it "answers validation_failed when the new password is too short" do
      user = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(user)

      patch "/api/v1/password", params: { current_password: password, password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "keeps the current session alive while revoking every other one" do
      user = create_membership(organization, role: "owner")
      sign_in_via_api(email: user.email, password:)
      csrf_token = fetch_csrf_token
      other_organization = create(:organization)
      create(:membership, organization: other_organization, user:, role: "read_only")
      Identity::Session.start!(user:, organization: other_organization, ip: "203.0.113.9", user_agent: "spec")
      expect(Identity::Session.count).to eq(2)

      patch "/api/v1/password", params: { current_password: password, password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:no_content)
      expect(Identity::Session.count).to eq(1)

      get "/api/v1/session"
      expect(response.parsed_body.dig("data", "user", "id")).to eq(user.id)
    end

    it "rate limits repeated attempts from the same IP" do
      user = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(user)

      5.times do
        patch "/api/v1/password", params: { current_password: "senha-errada", password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      end

      patch "/api/v1/password", params: { current_password: "senha-errada", password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:too_many_requests)
      assert_response_schema_confirm(429)
    end
  end
end

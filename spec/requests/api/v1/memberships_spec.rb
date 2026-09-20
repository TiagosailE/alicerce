require "rails_helper"

RSpec.describe "Memberships API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }

  def create_membership(organization, role:, demo: false)
    user = create(:user, password:, demo:)
    membership = create(:membership, user:, organization:, role:)
    [ user, membership ]
  end

  def sign_in_and_csrf(user)
    sign_in_via_api(email: user.email, password:)
    fetch_csrf_token
  end

  describe "PATCH /api/v1/memberships/:id" do
    it "requires an existing session" do
      _member, membership = create_membership(organization, role: "sales")

      patch "/api/v1/memberships/#{membership.id}", params: { role: "finance" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      _member, membership = create_membership(organization, role: "sales")
      sign_in_via_api(email: owner.email, password:)

      patch "/api/v1/memberships/#{membership.id}", params: { role: "finance" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): only owner and admin manage members.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :forbidden, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        _member, membership = create_membership(organization, role: "sales")
        csrf_token = sign_in_and_csrf(actor)

        patch "/api/v1/memberships/#{membership.id}", params: { role: "finance" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "denies a demo owner (ADR 0008)" do
      demo_owner, = create_membership(organization, role: "owner", demo: true)
      _member, membership = create_membership(organization, role: "sales")
      csrf_token = sign_in_and_csrf(demo_owner)

      patch "/api/v1/memberships/#{membership.id}", params: { role: "finance" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:forbidden)
    end

    it "changes the member's role and revokes their other sessions" do
      owner, = create_membership(organization, role: "owner")
      member, membership = create_membership(organization, role: "sales")
      Identity::Session.start!(user: member, organization:, ip: "203.0.113.9", user_agent: "spec")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/memberships/#{membership.id}", params: { role: "finance" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      data = response.parsed_body.fetch("data")
      expect(data["role"]).to eq("finance")
      expect(data.dig("user", "id")).to eq(membership.user_id)
      expect(Identity::Session.where(user: member)).to be_empty
    end

    it "answers validation_failed for a role outside the fixed list" do
      owner, = create_membership(organization, role: "owner")
      _member, membership = create_membership(organization, role: "sales")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/memberships/#{membership.id}", params: { role: "manager" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "answers not_found for another organization's membership, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      _other_member, other_membership = create_membership(other_organization, role: "sales")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/memberships/#{other_membership.id}", params: { role: "finance" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      expect(other_membership.reload.role).to eq("sales")
    end

    it "answers last_owner when it would leave the organization without an owner" do
      owner, owner_membership = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/memberships/#{owner_membership.id}", params: { role: "admin" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("last_owner")
    end

    it "answers owner_required when an admin tries to promote a member to owner" do
      admin, = create_membership(organization, role: "admin")
      _member, membership = create_membership(organization, role: "sales")
      csrf_token = sign_in_and_csrf(admin)

      patch "/api/v1/memberships/#{membership.id}", params: { role: "owner" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("owner_required")
      expect(membership.reload.role).to eq("sales")
    end

    it "answers owner_required when an admin tries to demote an owner (self-promotion cannot dethrone the owner this way either)" do
      admin, = create_membership(organization, role: "admin")
      _owner, owner_membership = create_membership(organization, role: "owner")
      create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(admin)

      patch "/api/v1/memberships/#{owner_membership.id}", params: { role: "admin" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("owner_required")
      expect(owner_membership.reload.role).to eq("owner")
    end
  end

  describe "DELETE /api/v1/memberships/:id" do
    it "requires an existing session" do
      _member, membership = create_membership(organization, role: "sales")

      delete "/api/v1/memberships/#{membership.id}"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      _member, membership = create_membership(organization, role: "sales")
      sign_in_via_api(email: owner.email, password:)

      delete "/api/v1/memberships/#{membership.id}"

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): only owner and admin manage members.
    { "owner" => :no_content, "admin" => :no_content, "purchasing" => :forbidden, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        _member, membership = create_membership(organization, role: "sales")
        csrf_token = sign_in_and_csrf(actor)

        delete "/api/v1/memberships/#{membership.id}", headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "denies a demo owner (ADR 0008)" do
      demo_owner, = create_membership(organization, role: "owner", demo: true)
      _member, membership = create_membership(organization, role: "sales")
      csrf_token = sign_in_and_csrf(demo_owner)

      delete "/api/v1/memberships/#{membership.id}", headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:forbidden)
    end

    it "removes the member and revokes their session in this organization only" do
      owner, = create_membership(organization, role: "owner")
      member, membership = create_membership(organization, role: "sales")
      Identity::Session.start!(user: member, organization:, ip: "203.0.113.9", user_agent: "spec")
      other_organization_membership_org = create(:organization)
      set_current_tenant(other_organization_membership_org)
      create(:membership, organization: other_organization_membership_org, user: member, role: "read_only")
      Identity::Session.start!(user: member, organization: other_organization_membership_org, ip: "203.0.113.9", user_agent: "spec")
      csrf_token = sign_in_and_csrf(owner)

      delete "/api/v1/memberships/#{membership.id}", headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:no_content)
      assert_response_schema_confirm(204)
      expect(Identity::Membership.exists?(membership.id)).to be(false)
      expect(Identity::Session.where(user: member, organization:)).to be_empty
      expect(Identity::Session.where(user: member, organization: other_organization_membership_org)).not_to be_empty
    end

    it "answers not_found for another organization's membership, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      _other_member, other_membership = create_membership(other_organization, role: "sales")
      csrf_token = sign_in_and_csrf(owner)

      delete "/api/v1/memberships/#{other_membership.id}", headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      expect(Identity::Membership.exists?(other_membership.id)).to be(true)
    end

    it "answers last_owner when removing the organization's only owner" do
      owner, owner_membership = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      delete "/api/v1/memberships/#{owner_membership.id}", headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("last_owner")
    end

    it "answers owner_required when an admin tries to remove an owner" do
      admin, = create_membership(organization, role: "admin")
      _owner, owner_membership = create_membership(organization, role: "owner")
      create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(admin)

      delete "/api/v1/memberships/#{owner_membership.id}", headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("owner_required")
      expect(Identity::Membership.exists?(owner_membership.id)).to be(true)
    end
  end
end

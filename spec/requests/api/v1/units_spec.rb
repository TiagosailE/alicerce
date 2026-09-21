require "rails_helper"

RSpec.describe "Units API" do
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

  describe "GET /api/v1/units" do
    it "requires an existing session" do
      get "/api/v1/units"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/units"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's units, by code" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:unit, organization:, code: "SC", name: "Saco")
      create(:unit, organization:, code: "UN", name: "Unidade")
      set_current_tenant(other_organization)
      create(:unit, organization: other_organization, code: "AA", name: "De outra organização")
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/units"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      body = response.parsed_body
      expect(body["data"].map { |unit| unit["code"] }).to eq([ "SC", "UN" ])
      expect(body["meta"]).to eq("page" => 1, "per_page" => 25, "total" => 2)
    end
  end

  describe "GET /api/v1/units/:id" do
    it "answers not_found for another organization's unit" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_unit = create(:unit, organization: other_organization)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/units/#{other_unit.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        unit = create(:unit, organization:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/units/#{unit.id}"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end
  end

  describe "POST /api/v1/units" do
    it "requires an existing session" do
      post "/api/v1/units", params: { code: "SC", name: "Saco" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/units", params: { code: "SC", name: "Saco" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        csrf_token = sign_in_and_csrf(actor)

        post "/api/v1/units", params: { code: "SC", name: "Saco" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "creates a unit scoped to the current organization" do
      owner, = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/units", params: { code: "SC", name: "Saco" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body.fetch("data")
      expect(data["code"]).to eq("SC")
      set_current_tenant(organization)
      expect(Catalog::Unit.sole.organization).to eq(organization)
    end

    it "answers validation_failed for a duplicate code" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:unit, organization:, code: "SC")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/units", params: { code: "SC", name: "Outro saco" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
  end

  describe "PATCH /api/v1/units/:id" do
    it "answers not_found for another organization's unit, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_unit = create(:unit, organization: other_organization, code: "SC")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/units/#{other_unit.id}", params: { code: "XX", name: "X", active: true }, as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      # The request's own tenant setting is cleared on this same connection
      # once it finishes (ADR 0003); re-apply it before querying an
      # RLS-protected table again, same as invitations_spec.rb.
      set_current_tenant(other_organization)
      expect(other_unit.reload.code).to eq("SC")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        unit = create(:unit, organization:)
        csrf_token = sign_in_and_csrf(actor)

        patch "/api/v1/units/#{unit.id}", params: { code: unit.code, name: "Novo nome", active: true }, as: :json,
          headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "updates the unit and can deactivate it" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      unit = create(:unit, organization:, active: true)
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/units/#{unit.id}", params: { code: unit.code, name: unit.name, active: false }, as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      set_current_tenant(organization)
      expect(unit.reload.active).to be(false)
    end
  end
end

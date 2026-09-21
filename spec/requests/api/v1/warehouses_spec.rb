require "rails_helper"

RSpec.describe "Warehouses API" do
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

  describe "GET /api/v1/warehouses" do
    it "requires an existing session" do
      get "/api/v1/warehouses"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/warehouses"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's warehouses, by name" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:warehouse, organization:, name: "Pátio")
      create(:warehouse, organization:, name: "Loja")
      set_current_tenant(other_organization)
      create(:warehouse, organization: other_organization, name: "De outra organização")
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/warehouses"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      names = response.parsed_body["data"].map { |warehouse| warehouse["name"] }
      expect(names).to eq([ "Loja", "Pátio" ])
    end
  end

  describe "GET /api/v1/warehouses/:id" do
    it "answers not_found for another organization's warehouse" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_warehouse = create(:warehouse, organization: other_organization)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/warehouses/#{other_warehouse.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        warehouse = create(:warehouse, organization:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/warehouses/#{warehouse.id}"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end
  end

  describe "POST /api/v1/warehouses" do
    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/warehouses", params: { name: "Loja" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        csrf_token = sign_in_and_csrf(actor)

        post "/api/v1/warehouses", params: { name: "Loja" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "answers validation_failed for a duplicate name" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:warehouse, organization:, name: "Loja")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/warehouses", params: { name: "loja" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
  end

  describe "PATCH /api/v1/warehouses/:id" do
    it "answers not_found for another organization's warehouse, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_warehouse = create(:warehouse, organization: other_organization, name: "Original")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/warehouses/#{other_warehouse.id}", params: { name: "Alterado", active: true }, as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      # The request's own tenant setting is cleared on this same connection
      # once it finishes (ADR 0003); re-apply it before querying an
      # RLS-protected table again, same as categories_spec.rb.
      set_current_tenant(other_organization)
      expect(other_warehouse.reload.name).to eq("Original")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        warehouse = create(:warehouse, organization:)
        csrf_token = sign_in_and_csrf(actor)

        patch "/api/v1/warehouses/#{warehouse.id}", params: { name: "Novo nome", active: true }, as: :json,
          headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "can deactivate a warehouse" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      warehouse = create(:warehouse, organization:, active: true)
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/warehouses/#{warehouse.id}", params: { name: warehouse.name, active: false }, as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:ok)
      set_current_tenant(organization)
      expect(warehouse.reload.active).to be(false)
    end
  end
end

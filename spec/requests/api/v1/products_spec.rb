require "rails_helper"

RSpec.describe "Products API" do
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

  def create_unit(organization, code: "UN")
    set_current_tenant(organization)
    create(:unit, organization:, code:)
  end

  describe "GET /api/v1/products" do
    it "requires an existing session" do
      get "/api/v1/products"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/products"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's products, by name, with their unit and conversion" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      unidade = create(:unit, organization:, code: "UN", name: "Unidade")
      milheiro = create(:unit, organization:, code: "MIL", name: "Milheiro")
      product = create(:product, organization:, sku: "TIJ-001", name: "Tijolo", stock_unit: unidade)
      create(:unit_conversion, organization:, product:, purchase_unit: milheiro, factor: "1000")
      set_current_tenant(other_organization)
      other_unit = create(:unit, organization: other_organization)
      create(:product, organization: other_organization, name: "De outra organização", stock_unit: other_unit)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/products"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      body = response.parsed_body
      expect(body["data"].length).to eq(1)
      data = body["data"].first
      expect(data["sku"]).to eq("TIJ-001")
      expect(data["stock_unit"]["code"]).to eq("UN")
      expect(data["unit_conversion"]["purchase_unit"]["code"]).to eq("MIL")
      expect(data["unit_conversion"]["factor"]).to eq("1000.0")
      expect(data["category"]).to be_nil
    end

    it "filters by category, active state and a name/sku search" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      unidade = create(:unit, organization:)
      cimento = create(:category, organization:, name: "Cimento")
      ferragens = create(:category, organization:, name: "Ferragens")
      create(:product, organization:, sku: "CIM-001", name: "Cimento CPII", category: cimento, stock_unit: unidade)
      create(:product, organization:, sku: "VER-001", name: "Vergalhão", category: ferragens, stock_unit: unidade, active: false)
      create(:product, organization:, sku: "TIJ-001", name: "Tijolo", stock_unit: unidade)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/products", params: { category_id: cimento.id }
      expect(response.parsed_body["data"].map { |p| p["sku"] }).to eq([ "CIM-001" ])

      get "/api/v1/products", params: { active: false }
      expect(response.parsed_body["data"].map { |p| p["sku"] }).to eq([ "VER-001" ])

      get "/api/v1/products", params: { q: "tijo" }
      expect(response.parsed_body["data"].map { |p| p["sku"] }).to eq([ "TIJ-001" ])
    end
  end

  describe "GET /api/v1/products/:id" do
    it "answers not_found for another organization's product" do
      owner, = create_membership(organization, role: "owner")
      other_unit = create_unit(other_organization)
      set_current_tenant(other_organization)
      other_product = create(:product, organization: other_organization, stock_unit: other_unit)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/products/#{other_product.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        unidade = create_unit(organization)
        set_current_tenant(organization)
        product = create(:product, organization:, stock_unit: unidade)
        create(:unit_conversion, organization:, product:, purchase_unit: unidade)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/products/#{product.id}"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end
  end

  describe "POST /api/v1/products" do
    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      unidade = create_unit(organization)
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/products", params: { sku: "TIJ-001", name: "Tijolo", stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        unidade = create_unit(organization)
        csrf_token = sign_in_and_csrf(actor)

        post "/api/v1/products",
          params: { sku: "TIJ-001", name: "Tijolo", stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1" },
          as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "creates a product with its unit conversion and an optional category" do
      owner, = create_membership(organization, role: "owner")
      unidade = create_unit(organization, code: "UN")
      milheiro = create_unit(organization, code: "MIL")
      set_current_tenant(organization)
      category = create(:category, organization:)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/products",
        params: { sku: "TIJ-001", name: "Tijolo", category_id: category.id,
                  stock_unit_id: unidade.id, purchase_unit_id: milheiro.id, factor: "1000" },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      assert_response_schema_confirm(201)
      data = response.parsed_body.fetch("data")
      expect(data["category"]["id"]).to eq(category.id)
      expect(data["unit_conversion"]["factor"]).to eq("1000.0")
    end

    it "answers validation_failed for a category_id belonging to another organization" do
      owner, = create_membership(organization, role: "owner")
      unidade = create_unit(organization)
      set_current_tenant(other_organization)
      other_category = create(:category, organization: other_organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/products",
        params: { sku: "TIJ-001", name: "Tijolo", category_id: other_category.id,
                  stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1" },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      set_current_tenant(organization)
      expect(Catalog::Product.count).to eq(0)
    end

    it "answers validation_failed for a category_id that does not exist at all" do
      owner, = create_membership(organization, role: "owner")
      unidade = create_unit(organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/products",
        params: { sku: "TIJ-001", name: "Tijolo", category_id: 0,
                  stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "1" },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "answers validation_failed when the factor is not positive" do
      owner, = create_membership(organization, role: "owner")
      unidade = create_unit(organization)
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/products",
        params: { sku: "TIJ-001", name: "Tijolo", stock_unit_id: unidade.id, purchase_unit_id: unidade.id, factor: "0" },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
  end

  describe "PATCH /api/v1/products/:id" do
    def create_product_with_conversion
      unidade = create_unit(organization, code: "UN")
      milheiro = create_unit(organization, code: "MIL")
      set_current_tenant(organization)
      product = create(:product, organization:, sku: "TIJ-001", name: "Tijolo", stock_unit: unidade)
      create(:unit_conversion, organization:, product:, purchase_unit: milheiro, factor: "1000")
      [ product, unidade, milheiro ]
    end

    it "answers not_found for another organization's product, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      other_unit = create_unit(other_organization)
      set_current_tenant(other_organization)
      other_product = create(:product, organization: other_organization, stock_unit: other_unit, name: "Original")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/products/#{other_product.id}",
        params: { sku: other_product.sku, name: "Alterado", stock_unit_id: other_unit.id,
                  purchase_unit_id: other_unit.id, factor: "1", active: true },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      # The request's own tenant setting is cleared on this same connection
      # once it finishes (ADR 0003); re-apply it before querying an
      # RLS-protected table again, same as invitations_spec.rb.
      set_current_tenant(other_organization)
      expect(other_product.reload.name).to eq("Original")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        product, unidade, milheiro = create_product_with_conversion
        csrf_token = sign_in_and_csrf(actor)

        patch "/api/v1/products/#{product.id}",
          params: { sku: product.sku, name: "Novo nome", stock_unit_id: unidade.id,
                    purchase_unit_id: milheiro.id, factor: "1000", active: true },
          as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "answers validation_failed when updated with a category_id belonging to another organization" do
      owner, = create_membership(organization, role: "owner")
      product, unidade, milheiro = create_product_with_conversion
      set_current_tenant(other_organization)
      other_category = create(:category, organization: other_organization)
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/products/#{product.id}",
        params: { sku: product.sku, name: product.name, category_id: other_category.id,
                  stock_unit_id: unidade.id, purchase_unit_id: milheiro.id, factor: "1000", active: true },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
      set_current_tenant(organization)
      expect(product.reload.category_id).to be_nil
    end

    it "updates the product and its unit conversion together" do
      owner, = create_membership(organization, role: "owner")
      product, unidade, = create_product_with_conversion
      set_current_tenant(organization)
      saco = create(:unit, organization:, code: "SC")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/products/#{product.id}",
        params: { sku: product.sku, name: "Tijolo 8 furos", stock_unit_id: unidade.id,
                  purchase_unit_id: saco.id, factor: "50", active: true },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      data = response.parsed_body.fetch("data")
      expect(data["name"]).to eq("Tijolo 8 furos")
      expect(data["unit_conversion"]["purchase_unit"]["code"]).to eq("SC")
      expect(data["unit_conversion"]["factor"]).to eq("50.0")
    end
  end
end

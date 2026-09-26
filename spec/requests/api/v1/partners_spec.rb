require "rails_helper"

RSpec.describe "Partners API" do
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

  def partner_params(overrides = {})
    { name: "Marcos Pereira", document_type: "cpf", document_number: DocumentNumberGenerator.cpf,
      customer: true, supplier: false }.merge(overrides)
  end

  describe "GET /api/v1/partners" do
    it "requires an existing session" do
      get "/api/v1/partners"

      expect(response).to have_http_status(:unauthorized)
      assert_response_schema_confirm(401)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/partners"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "lists only the current organization's partners, by name" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:partner, organization:, name: "Zeca")
      create(:partner, organization:, name: "Ana")
      set_current_tenant(other_organization)
      create(:partner, organization: other_organization, name: "De outra organização")
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/partners"

      expect(response).to have_http_status(:ok)
      assert_response_schema_confirm(200)
      names = response.parsed_body["data"].map { |partner| partner["name"] }
      expect(names).to eq([ "Ana", "Zeca" ])
    end

    it "filters by customer and supplier" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      create(:partner, organization:, name: "Cliente", customer: true, supplier: false)
      create(:partner, :supplier, organization:, name: "Fornecedor")
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/partners", params: { supplier: true }

      expect(response).to have_http_status(:ok)
      names = response.parsed_body["data"].map { |partner| partner["name"] }
      expect(names).to eq([ "Fornecedor" ])
    end
  end

  describe "GET /api/v1/partners/:id" do
    it "answers not_found for another organization's partner" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_partner = create(:partner, organization: other_organization)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/partners/#{other_partner.id}"

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
    end

    # Role matrix (ADR 0008): every role can read master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :ok,
      "finance" => :ok, "read_only" => :ok }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        partner = create(:partner, organization:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/partners/#{partner.id}"

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "returns the document_number decrypted" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      cpf = DocumentNumberGenerator.cpf
      partner = create(:partner, organization:, document_number: cpf)
      sign_in_via_api(email: owner.email, password:)

      get "/api/v1/partners/#{partner.id}"

      expect(response.parsed_body.dig("data", "document_number")).to eq(cpf)
    end
  end

  # ADR 0014: a page of up to 100 partners must not be a bulk export of
  # personal data, and the roles that only read do not need the full CPF.
  describe "personal data visibility" do
    let(:cpf) { DocumentNumberGenerator.cpf }
    let(:cnpj) { DocumentNumberGenerator.cnpj }

    before do
      set_current_tenant(organization)
      @person = create(:partner, organization:, name: "Marcos Pereira", document_type: "cpf", document_number: cpf,
        email: "marcos@example.com", phone: "71999990000")
      @company = create(:partner, organization:, name: "Cimento SA", document_type: "cnpj", document_number: cnpj,
        email: "contato@example.com", phone: "7133330000", customer: false, supplier: true)
    end

    %w[owner admin purchasing sales finance read_only].each do |role|
      it "lists a masked CPF, a full CNPJ and no e-mail or phone for the #{role} role" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/partners"

        expect(response).to have_http_status(:ok)
        assert_response_schema_confirm(200)
        rows = response.parsed_body["data"].index_by { |row| row["id"] }
        expect(rows[@person.id]["document_number"]).to eq("***#{cpf[3, 6]}**")
        expect(rows[@company.id]["document_number"]).to eq(cnpj)
        expect(rows.values.flat_map(&:keys).uniq)
          .to match_array(%w[id name document_type document_number customer supplier active])
      end
    end

    %w[owner admin purchasing sales finance].each do |role|
      it "shows the #{role} role the full record" do
        actor, = create_membership(organization, role:)
        sign_in_via_api(email: actor.email, password:)

        get "/api/v1/partners/#{@person.id}"

        assert_response_schema_confirm(200)
        expect(response.parsed_body["data"]).to include(
          "document_number" => cpf, "email" => "marcos@example.com", "phone" => "71999990000",
          "personal_data_visible" => true
        )
      end
    end

    it "shows the read_only role a masked CPF and no e-mail or phone, and says so" do
      actor, = create_membership(organization, role: "read_only")
      sign_in_via_api(email: actor.email, password:)

      get "/api/v1/partners/#{@person.id}"

      assert_response_schema_confirm(200)
      expect(response.parsed_body["data"]).to include(
        "document_number" => "***#{cpf[3, 6]}**", "email" => nil, "phone" => nil, "personal_data_visible" => false
      )
      expect(response.body).not_to include(cpf)
      expect(response.body).not_to include("marcos@example.com")
    end

    it "shows the read_only role a company's CNPJ in full" do
      actor, = create_membership(organization, role: "read_only")
      sign_in_via_api(email: actor.email, password:)

      get "/api/v1/partners/#{@company.id}"

      expect(response.parsed_body.dig("data", "document_number")).to eq(cnpj)
    end
  end

  describe "POST /api/v1/partners" do
    it "requires the CSRF token from a prior GET" do
      owner, = create_membership(organization, role: "owner")
      sign_in_via_api(email: owner.email, password:)

      post "/api/v1/partners", params: partner_params, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :created, "admin" => :created, "purchasing" => :created, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        csrf_token = sign_in_and_csrf(actor)

        post "/api/v1/partners", params: partner_params, as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
        expect(response.parsed_body.dig("error", "code")).to eq("forbidden") if expected_status == :forbidden
      end
    end

    it "creates the partner visible only to the current organization" do
      owner, = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/partners", params: partner_params, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      set_current_tenant(organization)
      expect(Catalog::Partner.count).to eq(1)
      set_current_tenant(other_organization)
      expect(Catalog::Partner.count).to eq(0)
    end

    it "answers validation_failed for a document_number that fails the checksum" do
      owner, = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/partners", params: partner_params(document_number: "12345678900"), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "answers validation_failed when neither customer nor supplier is set" do
      owner, = create_membership(organization, role: "owner")
      csrf_token = sign_in_and_csrf(owner)

      post "/api/v1/partners", params: partner_params(customer: false, supplier: false), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
  end

  describe "PATCH /api/v1/partners/:id" do
    it "answers not_found for another organization's partner, leaving it unchanged" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(other_organization)
      other_partner = create(:partner, organization: other_organization, name: "Original")
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/partners/#{other_partner.id}",
        params: { name: "Alterado", document_type: other_partner.document_type, document_number: other_partner.document_number,
          customer: true, supplier: false, active: true, revision: 0 },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:not_found)
      assert_response_schema_confirm(404)
      set_current_tenant(other_organization)
      expect(other_partner.reload.name).to eq("Original")
    end

    # Role matrix (ADR 0008): owner, admin and purchasing manage master data.
    { "owner" => :ok, "admin" => :ok, "purchasing" => :ok, "sales" => :forbidden,
      "finance" => :forbidden, "read_only" => :forbidden }.each do |role, expected_status|
      it "answers #{expected_status} for the #{role} role" do
        actor, = create_membership(organization, role:)
        set_current_tenant(organization)
        partner = create(:partner, organization:)
        csrf_token = sign_in_and_csrf(actor)

        patch "/api/v1/partners/#{partner.id}",
          params: { name: "Novo nome", document_type: partner.document_type, document_number: partner.document_number,
            customer: true, supplier: false, active: true, revision: 0 },
          as: :json, headers: { "X-CSRF-Token" => csrf_token }

        expect(response).to have_http_status(expected_status)
        assert_response_schema_confirm(response.status)
      end
    end

    it "can deactivate a partner" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      partner = create(:partner, organization:, active: true)
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/partners/#{partner.id}",
        params: { name: partner.name, document_type: partner.document_type, document_number: partner.document_number,
          customer: true, supplier: false, active: false, revision: 0 },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:ok)
      set_current_tenant(organization)
      expect(partner.reload.active).to be(false)
    end

    it "answers 409 stale, writing nothing, when the partner changed since it was read" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      partner = create(:partner, organization:, name: "Original")
      csrf_token = sign_in_and_csrf(owner)
      params = { name: "Primeira edicao", document_type: partner.document_type, document_number: partner.document_number,
                 customer: true, supplier: false, active: true, revision: 0 }

      patch "/api/v1/partners/#{partner.id}", params:, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      expect(response.parsed_body.dig("data", "revision")).to eq(1)

      patch "/api/v1/partners/#{partner.id}", params: params.merge(name: "Edicao antiga"), as: :json,
        headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:conflict)
      assert_response_schema_confirm(409)
      expect(response.parsed_body.dig("error", "code")).to eq("stale")
      set_current_tenant(organization)
      expect(partner.reload.name).to eq("Primeira edicao")
    end

    it "answers validation_failed when the revision is missing" do
      owner, = create_membership(organization, role: "owner")
      set_current_tenant(organization)
      partner = create(:partner, organization:)
      csrf_token = sign_in_and_csrf(owner)

      patch "/api/v1/partners/#{partner.id}",
        params: { name: "Sem revisao", document_type: partner.document_type, document_number: partner.document_number,
                  customer: true, supplier: false, active: true },
        as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "details", "fields")).to have_key("revision")
    end
  end
end

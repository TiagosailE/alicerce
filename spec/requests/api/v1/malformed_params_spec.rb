require "rails_helper"

# Values the query and command objects cannot handle must be a 422 in the
# shared error envelope, never an unhandled exception answering 500.
RSpec.describe "Malformed parameters" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }
  let(:owner) do
    user = create(:user, password:)
    create(:membership, user:, organization:, role: "owner")
    user
  end

  before do
    sign_in_via_api(email: owner.email, password:)
    @csrf_token = fetch_csrf_token
  end

  def expect_invalid(field = nil)
    expect(response).to have_http_status(:unprocessable_content)
    assert_response_schema_confirm(422)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    expect(response.parsed_body.dig("error", "details", "fields")).to have_key(field) if field
  end

  describe "pagination and filters that arrive as an array or a hash" do
    %w[units categories products partners warehouses memberships invitations stock_balances purchase_orders].each do |resource|
      it "answers 422 for page[] on /#{resource}" do
        get "/api/v1/#{resource}?page[]=1"

        expect_invalid("page")
      end

      it "answers 422 for per_page[a] on /#{resource}" do
        get "/api/v1/#{resource}?per_page[a]=1"

        expect_invalid("per_page")
      end
    end

    it "answers 422 for a q that is an array" do
      get "/api/v1/partners?q[]=Marcos"

      expect_invalid("q")
    end

    it "answers 422 for a category_id that is a hash" do
      get "/api/v1/products?category_id[a]=1"

      expect_invalid("category_id")
    end

    it "clamps a page number beyond any real page instead of overflowing the OFFSET" do
      get "/api/v1/units?page=99999999999999999999"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to eq([])
      expect(response.parsed_body.dig("meta", "page")).to eq(Pagination::MAX_PAGE)
    end

    it "still answers 200 for well formed pagination" do
      get "/api/v1/units?page=1&per_page=10"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "null bytes" do
    it "answers 422 for a null byte in a search term" do
      get "/api/v1/products?q=a%00b"

      expect_invalid
    end

    it "answers 422 for a null byte in a request body" do
      post "/api/v1/units", params: { code: "SC", name: "Sa\u0000co" }, as: :json,
        headers: { "X-CSRF-Token" => @csrf_token }

      expect_invalid
      set_current_tenant(organization)
      expect(Catalog::Unit.count).to eq(0)
    end

    it "answers 422 for a null byte nested inside a body" do
      post "/api/v1/products", params: { sku: "X", name: "Y", stock_unit_id: 1, purchase_unit_id: 1, factor: "1", category_id: [ "a\u0000" ] },
        as: :json, headers: { "X-CSRF-Token" => @csrf_token }

      expect_invalid
    end
  end
end

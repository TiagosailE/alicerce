require "rails_helper"

RSpec.describe "Password resets API" do
  let(:password) { "senha-de-teste-longa" }
  let(:organization) { create(:organization) }

  def fetch_csrf_token
    get "/api/v1/session"
    response.parsed_body.dig("data", "csrf_token")
  end

  describe "POST /api/v1/password_resets" do
    it "requires the CSRF token from a prior GET" do
      post "/api/v1/password_resets", params: { email: "alguem@alicerce.example" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "answers 204 and enqueues the mailer job with the given email" do
      user = create(:user, password:)
      create(:membership, organization:, user:, role: "owner")
      csrf_token = fetch_csrf_token

      expect {
        post "/api/v1/password_resets", params: { email: user.email }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      }.to have_enqueued_job(Identity::PasswordResetMailerJob).with(email: user.email)

      expect(response).to have_http_status(:no_content)
      assert_response_schema_confirm(204)
    end

    it "answers 204 and enqueues the same way for an unknown email (ADR 0007: uniform response)" do
      csrf_token = fetch_csrf_token

      expect {
        post "/api/v1/password_resets", params: { email: "ninguem@alicerce.example" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      }.to have_enqueued_job(Identity::PasswordResetMailerJob).with(email: "ninguem@alicerce.example")

      expect(response).to have_http_status(:no_content)
      assert_response_schema_confirm(204)
    end

    it "answers 204 and enqueues the same way for a demo account (ADR 0008: the job itself skips sending)" do
      demo_user = create(:user, demo: true, password:)
      create(:membership, organization:, user: demo_user, role: "owner")
      csrf_token = fetch_csrf_token

      expect {
        post "/api/v1/password_resets", params: { email: demo_user.email }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      }.to have_enqueued_job(Identity::PasswordResetMailerJob).with(email: demo_user.email)

      expect(response).to have_http_status(:no_content)
    end

    it "answers validation_failed when the email is missing" do
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets", params: {}, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "rate limits repeated attempts from the same IP" do
      10.times do
        csrf_token = fetch_csrf_token
        post "/api/v1/password_resets", params: { email: "ninguem@alicerce.example" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      end
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets", params: { email: "ninguem@alicerce.example" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:too_many_requests)
      assert_response_schema_confirm(429)
    end
  end

  describe "POST /api/v1/password_resets/completion" do
    # has_secure_password's reset_token machinery is stateless: any token
    # generated for this user is valid until it individually expires, so
    # calling it here directly (rather than through the request email, only
    # tested through the mailer job) is a valid token for the same purpose.
    def token_for(user) = user.password_reset_token

    it "requires the CSRF token from a prior GET" do
      user = create(:user, password:)
      token = token_for(user)

      post "/api/v1/password_resets/completion", params: { token:, password: "nova-senha-bem-longa" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_csrf_token")
    end

    it "sets the new password and lets the user sign in with it, starting no session" do
      user = create(:user, password:)
      create(:membership, organization:, user:, role: "owner")
      token = token_for(user)
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets/completion",
        params: { token:, password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:no_content)
      assert_response_schema_confirm(204)

      get "/api/v1/session"
      expect(response.parsed_body.dig("data", "user")).to be_nil

      sign_in_csrf = fetch_csrf_token
      post "/api/v1/session", params: { email: user.email, password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => sign_in_csrf }
      expect(response).to have_http_status(:created)
    end

    it "answers invalid_token for an unknown token" do
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets/completion",
        params: { token: "not-a-real-token", password: "nova-senha-bem-longa" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_token")
    end

    it "answers validation_failed when the new password is too short" do
      user = create(:user, password:)
      token = token_for(user)
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets/completion", params: { token:, password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:unprocessable_content)
      assert_response_schema_confirm(422)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end

    it "rate limits repeated attempts from the same IP" do
      user = create(:user, password:)
      token = token_for(user)

      10.times do
        csrf_token = fetch_csrf_token
        post "/api/v1/password_resets/completion", params: { token:, password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }
      end
      csrf_token = fetch_csrf_token

      post "/api/v1/password_resets/completion", params: { token:, password: "curta" }, as: :json, headers: { "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:too_many_requests)
      assert_response_schema_confirm(429)
    end
  end
end

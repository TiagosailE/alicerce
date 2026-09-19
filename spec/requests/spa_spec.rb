require "rails_helper"

RSpec.describe "SPA shell" do
  it "serves the shell at the root with a strict content security policy" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include('<div id="root">')
    expect(response.headers["Cache-Control"]).to include("no-cache")

    csp = response.headers["Content-Security-Policy"]
    expect(csp).to include("default-src 'none'", "script-src 'self'", "frame-ancestors 'none'")
    expect(csp).not_to include("unsafe-inline")
  end

  it "serves the same shell for deep links so the client router can resolve them" do
    get "/estoque/produtos/42"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<div id="root">')
  end

  it "forbids framing and sends a restrictive permissions policy" do
    get "/"

    expect(response.headers["X-Frame-Options"]).to eq("DENY")
    expect(response.headers["Permissions-Policy"]).to include("camera=()", "geolocation=()")
  end

  it "never answers API paths with the shell, answering the JSON error envelope instead" do
    %w[/api /api/ /api/v1/unknown].each do |path|
      get path

      expect(response).to have_http_status(:not_found), path
      expect(response.body).not_to include('<div id="root">')
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end
  end

  it "never serves the shell as a static file, which would skip the CSP" do
    %w[/spa /spa/ /spa/index.html].each do |path|
      get path

      expect(response).to have_http_status(:not_found), path
    end
  end

  it "answers 404 to requests that are not page navigations" do
    get "/estoque/produtos", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:not_found)

    %w[/favicon.ico /wp-login.php].each do |path|
      get path

      expect(response).to have_http_status(:not_found), path
    end
  end

  it "does not hijack the health check" do
    get "/up"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('<div id="root">')
  end

  it "answers 503 with instructions when the frontend was not built" do
    allow(Rails.configuration.x).to receive(:spa_index).and_return(Rails.root.join("tmp/missing.html"))

    get "/"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("npm --prefix frontend run build")
  end
end

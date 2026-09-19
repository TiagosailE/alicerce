# Boots the app with production settings and checks the security headers a
# browser would receive, without a database or a network. The HTTP to HTTPS
# redirect is not checked: TLS ends at the platform edge and assume_ssl makes
# Rails treat every request as HTTPS. Run by bin/ci:
#   RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 APP_HOST=ci.example bin/rails runner script/check_production_headers.rb
app = Rack::MockRequest.new(Rails.application)
host = Rails.application.config.hosts.first
https = { "HTTP_HOST" => host, "HTTP_X_FORWARDED_PROTO" => "https" }

checks = {
  "/ answers the shell" => -> { app.get("/", https).status == 200 },
  "HSTS on HTTPS responses" => -> { app.get("/", https).headers["strict-transport-security"].to_s.include?("max-age=") },
  "CSP without unsafe-inline" => -> { app.get("/", https).headers["content-security-policy"].to_s.then { |csp| csp.include?("default-src 'none'") && !csp.include?("unsafe-inline") } },
  "nosniff" => -> { app.get("/", https).headers["x-content-type-options"] == "nosniff" },
  "referrer policy" => -> { app.get("/", https).headers["referrer-policy"] == "strict-origin-when-cross-origin" },
  "the shell is never a static file" => -> { app.get("/spa/index.html", https).status == 404 },
  "hashed assets are immutable" => -> { Dir["public/spa/assets/*.js"].first.then { |js| js && app.get(js.delete_prefix("public"), https).headers["cache-control"].to_s.include?("immutable") } },
  "unknown host is refused" => -> { app.get("/", https.merge("HTTP_HOST" => "evil.example")).status == 403 },
  "/up stays reachable for the platform" => -> { app.get("/up", "HTTP_HOST" => "10.0.0.1").status == 200 }
}

failures = checks.reject { |_name, check| check.call }.keys
checks.each_key { |name| puts "#{failures.include?(name) ? "FAIL" : "ok  "} #{name}" }
exit(failures.empty? ? 0 : 1)

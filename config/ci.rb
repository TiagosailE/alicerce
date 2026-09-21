CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: TypeScript", "npm --prefix frontend run lint"
  step "Style: Formatting", "npm --prefix frontend run format:check"
  step "Types: TypeScript", "npm --prefix frontend run typecheck"
  step "Contract: OpenAPI types match docs/openapi/openapi.yaml",
    "npm --prefix frontend run generate:api && git diff --exit-code -- frontend/src/api/schema.d.ts"

  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: npm audit", "npm --prefix frontend audit --audit-level=high"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Tests: RSpec", "env CI=true COVERAGE_MIN_LINE=90 COVERAGE_MIN_BRANCH=80 bin/rspec"
  step "Tests: Vitest", "npm --prefix frontend test"

  step "Build: SPA", "npm --prefix frontend run build"
  step "Build: shell stays out of public", "test ! -e public/spa/index.html && test -f frontend/dist/index.html"
  step "Boot: production headers",
    "env RAILS_ENV=production BUNDLE_WITHOUT=development:test RAILS_LOG_LEVEL=fatal SECRET_KEY_BASE_DUMMY=1 " \
    "APP_HOST=ci.example AR_ENCRYPTION_PRIMARY_KEY=ci-primary-key AR_ENCRYPTION_DETERMINISTIC_KEY=ci-deterministic-key " \
    "AR_ENCRYPTION_KEY_DERIVATION_SALT=ci-key-derivation-salt bin/rails runner script/check_production_headers.rb"
end

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: TypeScript", "npm --prefix frontend run lint"
  step "Style: Formatting", "npm --prefix frontend run format:check"
  step "Types: TypeScript", "npm --prefix frontend run typecheck"

  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: npm audit", "npm --prefix frontend audit --audit-level=high"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Tests: RSpec", "env CI=true COVERAGE_MIN_LINE=90 COVERAGE_MIN_BRANCH=80 bin/rspec"
  step "Tests: Vitest", "npm --prefix frontend test"

  step "Build: SPA", "npm --prefix frontend run build"
end
